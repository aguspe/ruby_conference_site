require "test_helper"

class RsvpsControllerTest < ActionDispatch::IntegrationTest
  # Text unique to each partial, so a test can't pass on the other one's body.
  CONFIRMED_TEXT = "Your seat is reserved"
  WAITLIST_TEXT  = "you're on the waitlist"

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
    assert_no_difference "Rsvp.count" do
      post rsvps_path, params: params(rsvp: { email: "nope" })
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
    assert_no_difference "Rsvp.count" do
      post rsvps_path, params: params(rsvp: { email: "nope" })
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

    assert_no_difference "Rsvp.count" do
      post rsvps_path, params: params(company: "Spam Co")
    end
    assert_response :success
    assert_equal expected, response.body
  end

  test "a submission faster than the dwell threshold is discarded" do
    expected = genuine_success_body

    assert_no_difference "Rsvp.count" do
      post rsvps_path, params: params(t: timestamp_for(Time.current))
    end
    assert_response :success
    assert_equal expected, response.body
  end

  test "a tampered timestamp is discarded" do
    expected = genuine_success_body

    assert_no_difference "Rsvp.count" do
      post rsvps_path, params: params(t: "forged")
    end
    assert_response :success
    assert_equal expected, response.body
  end

  test "a timestamp older than the replay window is discarded" do
    expected = genuine_success_body
    stale = timestamp_for(Time.current, expires_in: 1.second)

    travel 2.seconds do
      assert_no_difference "Rsvp.count" do
        post rsvps_path, params: params(t: stale)
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
      assert_no_difference "Rsvp.count" do
        20.times do |i|
          post rsvps_path, params: params(t: captured, rsvp: { email: "replay#{i}@example.com" })
          assert_response :success
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
      assert_no_difference "Rsvp.count" do
        post rsvps_path, params: params(t: token)
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
      assert_no_difference "Rsvp.count", "shape #{shape.inspect} persisted a row" do
        post rsvps_path, params: base.merge(shape)
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

      assert_no_difference "Rsvp.count" do
        3.times do |i|
          post rsvps_path, params: params(rsvp: { email: "blocked#{i}@example.com" })
          assert_response :success
          assert_equal expected, response.body,
            "a rate-limited response must be byte-identical to a success"
        end
      end
    ensure
      Rails.cache = original
    end
  end
end
