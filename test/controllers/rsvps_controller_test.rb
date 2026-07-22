require "test_helper"

class RsvpsControllerTest < ActionDispatch::IntegrationTest
  # Text unique to each partial, so a test can't pass on the other one's body.
  CONFIRMED_TEXT = "Your seat is reserved"
  WAITLIST_TEXT  = "you're on the waitlist"
  WAITLIST_FULL_TEXT = "can't add your name today"

  # The organiser address the mailer resolves is env-dependent, and a test that
  # re-reads the same env var the implementation reads would pass by
  # construction. These tests pin a literal instead and set the var to match.
  ORGANISER = "organiser@example.test"

  def with_organiser_email(address)
    original = ENV["ORGANISER_EMAIL"]
    ENV["ORGANISER_EMAIL"] = address
    yield
  ensure
    original.nil? ? ENV.delete("ORGANISER_EMAIL") : ENV["ORGANISER_EMAIL"] = original
  end

  def fill_room
    Rsvp::CAPACITY.times { |i| Rsvp.reserve(name: "Seat #{i}", email: "seat#{i}@example.com") }
  end

  def fill_waitlist(count)
    count.times { |i| Rsvp.reserve(name: "Wait #{i}", email: "wait#{i}@example.com") }
  end

  def verifier
    ActiveSupport::MessageVerifier.new(
      Rails.application.secret_key_base, digest: "SHA256"
    )
  end

  def timestamp_for(time, expires_in: RsvpsHelper::MAX_DWELL)
    verifier.generate(time.to_i, expires_in: expires_in)
  end

  # A timestamp old enough to pass the minimum-dwell check.
  def valid_timestamp = timestamp_for(10.seconds.ago)

  def params(overrides = {})
    { rsvp: { name: "Ada", email: "ada@example.com", dietary: "" },
      company: "",
      t: valid_timestamp }.deep_merge(overrides)
  end

  # Every response the form can receive must be addressed to the frame the
  # form targets, or Turbo renders "Content missing" instead of the partial.
  def assert_rsvp_frame
    assert_select "turbo-frame#rsvp_form", 1,
      "response must carry <turbo-frame id=\"rsvp_form\">, got: #{response.body}"
  end

  # The body a genuine, successful reservation produces. Every silently
  # discarded request must be byte-identical to this.
  def genuine_success_body
    post rsvps_path, params: params(rsvp: { name: "Real", email: "real@example.com" })
    assert_response :success
    body = response.body
    Rsvp.destroy_all
    body
  end

  test "a valid rsvp is stored and confirmed" do
    assert_difference "Rsvp.count", 1 do
      post rsvps_path, params: params
    end
    assert_response :success
    assert_rsvp_frame
    assert_match CONFIRMED_TEXT, response.body
    assert_no_match WAITLIST_TEXT, response.body
    assert_not Rsvp.last.waitlisted?
  end

  test "an invalid rsvp re-renders the form with errors and stores nothing" do
    assert_no_emails do
      assert_no_difference "Rsvp.count" do
        post rsvps_path, params: params(rsvp: { email: "nope" })
      end
    end
    assert_response :unprocessable_entity
    assert_rsvp_frame
    assert_match "not a valid email address", response.body
  end

  test "an invalid rsvp at full capacity renders the form, not the waitlist" do
    Rsvp::CAPACITY.times { |i| Rsvp.reserve(name: "G#{i}", email: "g#{i}@example.com") }

    # At a full house `reserve` sets waitlisted = true provisionally, so a
    # controller that checked `waitlisted?` before `persisted?` would answer a
    # never-saved record with a waitlist confirmation.
    assert_no_emails do
      assert_no_difference "Rsvp.count" do
        post rsvps_path, params: params(rsvp: { email: "nope" })
      end
    end
    assert_response :unprocessable_entity
    assert_rsvp_frame
    assert_match "not a valid email address", response.body
    assert_no_match WAITLIST_TEXT, response.body
    assert_no_match CONFIRMED_TEXT, response.body
  end

  test "an rsvp past capacity is waitlisted" do
    Rsvp::CAPACITY.times { |i| Rsvp.reserve(name: "G#{i}", email: "g#{i}@example.com") }

    post rsvps_path, params: params
    assert_response :success
    assert_rsvp_frame
    assert Rsvp.last.waitlisted?
    assert_match WAITLIST_TEXT, response.body
    assert_no_match CONFIRMED_TEXT, response.body
  end

  # --- the waitlist bound ---

  test "the last place on the waitlist is accepted, and mails" do
    fill_room
    fill_waitlist(Rsvp::WAITLIST_CAPACITY - 1)

    assert_emails 2 do
      assert_difference "Rsvp.count", 1 do
        post rsvps_path, params: params
      end
    end
    assert_response :success
    assert_rsvp_frame
    assert_match WAITLIST_TEXT, response.body
    assert Rsvp.last.waitlisted?
    assert_equal Rsvp::WAITLIST_CAPACITY, Rsvp.waitlist_taken
  end

  test "an rsvp past the waitlist bound is rejected, persisting nothing and mailing nothing" do
    fill_room
    fill_waitlist(Rsvp::WAITLIST_CAPACITY)

    assert_no_emails do
      assert_no_difference "Rsvp.count" do
        post rsvps_path, params: params
      end
    end
    assert_response :unprocessable_entity
    assert_rsvp_frame
    assert_match WAITLIST_FULL_TEXT, response.body
    assert_no_match CONFIRMED_TEXT, response.body
    assert_no_match WAITLIST_TEXT, response.body
    assert_not Rsvp.exists?(email: "ada@example.com")
  end

  # The abuse probe from the review, as a regression test: with the room full,
  # a caller hammering the endpoint with fresh addresses must stop adding rows
  # and stop generating mail once the waitlist bound is reached.
  test "rows and mail both stop growing once the waitlist is full" do
    fill_room
    fill_waitlist(Rsvp::WAITLIST_CAPACITY)
    ceiling = Rsvp.count

    assert_no_emails do
      assert_no_difference "Rsvp.count" do
        10.times do |i|
          post rsvps_path, params: params(rsvp: { name: "Abuse", email: "abuse#{i}@example.com" })
          assert_response :unprocessable_entity
        end
      end
    end
    assert_equal ceiling, Rsvp.count
    assert_equal Rsvp::CAPACITY + Rsvp::WAITLIST_CAPACITY, ceiling
  end

  test "the landing page renders the rsvp form" do
    get root_path
    assert_select "form.rsvp-form"
    assert_select "input[name=?]", "rsvp[name]"
    assert_select "input[name=?]", "rsvp[email]"
  end

  test "waitlisted cannot be forced true via mass assignment" do
    assert_difference "Rsvp.count", 1 do
      post rsvps_path, params: params(rsvp: { waitlisted: false })
    end
    assert_response :success
    assert_not Rsvp.last.waitlisted?

    # Fill the room, then try to force a confirmed seat via a raw param that
    # is not in the permitted list.
    Rsvp.destroy_all
    Rsvp::CAPACITY.times { |i| Rsvp.reserve(name: "G#{i}", email: "g#{i}@example.com") }

    post rsvps_path, params: params(rsvp: { name: "Late Comer", email: "late@example.com", waitlisted: false })
    assert_response :success
    assert Rsvp.last.waitlisted?, "waitlisted must not be settable from params"
  end

  # --- silent filters: every one must be indistinguishable from success ---

  test "a filled honeypot is silently discarded" do
    expected = genuine_success_body

    assert_no_emails do
      assert_no_difference "Rsvp.count" do
        post rsvps_path, params: params(company: "Spam Co")
      end
    end
    assert_response :success
    assert_equal expected, response.body
  end

  test "a submission faster than the dwell threshold is discarded" do
    expected = genuine_success_body

    assert_no_emails do
      assert_no_difference "Rsvp.count" do
        post rsvps_path, params: params(t: timestamp_for(Time.current))
      end
    end
    assert_response :success
    assert_equal expected, response.body
  end

  test "a tampered timestamp is discarded" do
    expected = genuine_success_body

    assert_no_emails do
      assert_no_difference "Rsvp.count" do
        post rsvps_path, params: params(t: "forged")
      end
    end
    assert_response :success
    assert_equal expected, response.body
  end

  test "a timestamp older than the replay window is discarded" do
    expected = genuine_success_body
    stale = timestamp_for(Time.current, expires_in: 1.second)

    travel 2.seconds do
      assert_no_emails do
        assert_no_difference "Rsvp.count" do
          post rsvps_path, params: params(t: stale)
        end
      end
    end
    assert_response :success
    assert_equal expected, response.body
  end

  test "a captured timestamp cannot be replayed past the expiry window" do
    captured = valid_timestamp

    # Inside the window it works exactly once per unique email.
    assert_difference "Rsvp.count", 1 do
      post rsvps_path, params: params(t: captured, rsvp: { email: "a@example.com" })
    end

    travel(RsvpsHelper::MAX_DWELL + 1.minute) do
      assert_no_emails do
        assert_no_difference "Rsvp.count" do
          20.times do |i|
            post rsvps_path, params: params(t: captured, rsvp: { email: "replay#{i}@example.com" })
            assert_response :success
          end
        end
      end
    end
  end

  # Every other replay test mints its own token via `timestamp_for`, supplying
  # `expires_in` itself — which only proves MessageVerifier honours the
  # option, not that `rsvp_form_timestamp` (the sole production generator)
  # actually passes it. This test uses the token the app itself renders, so
  # deleting `expires_in:` from `rsvp_form_timestamp` cannot leave the suite
  # green.
  test "the page's own rendered token cannot be replayed past the expiry window" do
    get root_path
    assert_response :success
    token = css_select("input[name='t']").first&.[]("value")
    assert token.present?, "could not find the rendered t token on the landing page"

    expected = genuine_success_body

    travel 31.minutes do
      assert_no_emails do
        assert_no_difference "Rsvp.count" do
          post rsvps_path, params: params(t: token)
        end
      end
      assert_response :success
      assert_equal expected, response.body
    end
  end

  test "a malformed rsvp param is indistinguishable from success and never raises" do
    expected = genuine_success_body

    hostile = [
      {},                                   # rsvp absent entirely
      { rsvp: {} },                         # empty hash (Rack drops it)
      { rsvp: "string" },                   # scalar
      { rsvp: %w[a b] },                    # array
      { rsvp: { name: { nested: "hash" } } } # nested hash where a scalar belongs
    ]

    hostile.each do |shape|
      base = { company: "", t: valid_timestamp }
      assert_no_emails do
        assert_no_difference "Rsvp.count", "shape #{shape.inspect} persisted a row" do
          post rsvps_path, params: base.merge(shape)
        end
      end
      assert_response :success, "shape #{shape.inspect} did not return 200"
      assert_equal expected, response.body,
        "shape #{shape.inspect} produced a distinguishable body"
    end
  end

  test "requests past the rate limit are silently discarded" do
    expected = genuine_success_body

    # The suite runs on :null_store, so `rate_limit` never engages by default.
    # Swap in a real store for this test only, and restore it afterwards.
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    begin
      # The limit is 5 per minute; the first 5 are genuine reservations.
      assert_difference "Rsvp.count", 5 do
        5.times do |i|
          post rsvps_path, params: params(rsvp: { email: "ok#{i}@example.com" })
          assert_response :success
        end
      end

      assert_no_emails do
        assert_no_difference "Rsvp.count" do
          3.times do |i|
            post rsvps_path, params: params(rsvp: { email: "blocked#{i}@example.com" })
            assert_response :success
            assert_equal expected, response.body,
              "a rate-limited response must be byte-identical to a success"
          end
        end
      end
    ensure
      Rails.cache = original
    end
  end

  # --- email delivery ---

  # A bare `assert_emails 2` pins only a count, so a controller that
  # sent `confirmation` twice — never notifying the organiser, and double-mailing
  # the attendee — would keep the suite green. This asserts identity: which
  # mailer went to which address, with which subject.
  test "a valid rsvp mails the attendee a confirmation and the organiser a notification" do
    with_organiser_email(ORGANISER) do
      ActionMailer::Base.deliveries.clear

      post rsvps_path, params: params

      deliveries = ActionMailer::Base.deliveries
      assert_equal 2, deliveries.size, "expected exactly one attendee mail and one organiser mail"
      assert_equal [ [ "ada@example.com" ], [ ORGANISER ] ], deliveries.map(&:to).sort_by(&:first)

      attendee = deliveries.find { |mail| mail.to == [ "ada@example.com" ] }
      organiser = deliveries.find { |mail| mail.to == [ ORGANISER ] }

      assert attendee, "no mail was addressed to the submitted attendee address"
      assert organiser, "no mail was addressed to the organiser address"
      assert_equal "Your seat at hygge.rb is reserved", attendee.subject
      assert_equal "New hygge.rb RSVP: Ada", organiser.subject
    end
  end

  test "a rejected rsvp sends nothing" do
    assert_no_emails do
      post rsvps_path, params: params(rsvp: { email: "nope" })
      post rsvps_path, params: params(company: "Spam Co")
    end
  end

  # Swaps the controller's logger for a captured one for the duration of a
  # block, so a test can assert on what got logged without touching the
  # global `Rails.logger` (which `RsvpsController#logger` does not delegate
  # to live — it delegates to `config.logger`, set once at boot).
  def capturing_rsvps_controller_log
    io = StringIO.new
    original = RsvpsController.logger
    RsvpsController.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    RsvpsController.logger = original
  end

  # Mail is delivered inline (`deliver_now`), not `deliver_later`, so there is
  # no separate job to run later — a mailer raising happens synchronously
  # inside the request. This proves the controller's own rescue absorbs that:
  # the reservation still commits, the response still succeeds, and the
  # failure is not silently dropped — it lands in the log.
  test "a mailer raising is caught, does not roll back the reservation or fail the request, and is logged" do
    RsvpMailer.class_eval do
      alias_method :original_confirmation, :confirmation
      define_method(:confirmation) { |*| raise "SMTP is on fire" }
    end

    begin
      log = capturing_rsvps_controller_log do
        assert_difference "Rsvp.count", 1 do
          assert_emails 1 do
            post rsvps_path, params: params
          end
        end
      end

      assert_response :success
      assert_rsvp_frame
      assert_match CONFIRMED_TEXT, response.body
      assert Rsvp.exists?(email: "ada@example.com"),
        "the reservation must survive a mail failure"

      assert_match(/rsvp mailer.*delivery failed.*SMTP is on fire/, log,
        "a mail failure must leave a log line, not disappear silently")
    ensure
      RsvpMailer.class_eval do
        remove_method :confirmation
        alias_method :confirmation, :original_confirmation
        remove_method :original_confirmation
      end
    end
  end
end
