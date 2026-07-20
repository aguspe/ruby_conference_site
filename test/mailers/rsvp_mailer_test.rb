require "test_helper"

class RsvpMailerTest < ActionMailer::TestCase
  setup do
    @rsvp = Rsvp.create!(name: "Ada", email: "ada@example.com", dietary: "no nuts")
  end

  test "confirmation goes to the attendee with the date and address" do
    mail = RsvpMailer.confirmation(@rsvp)
    assert_equal [ "ada@example.com" ], mail.to
    assert_equal "Your seat at hygge.rb is reserved", mail.subject
    assert_match "Ada", mail.body.to_s
    assert_match "28 November 2026", mail.body.to_s
    assert_match "Åboulevarden", mail.body.to_s
  end

  # Re-reading ENV["ORGANISER_EMAIL"] to build the expected value would make
  # this assertion true by construction whatever the mailer did. Each branch is
  # driven explicitly instead, against a pinned literal.
  def with_organiser_email(address)
    original = ENV["ORGANISER_EMAIL"]
    address.nil? ? ENV.delete("ORGANISER_EMAIL") : ENV["ORGANISER_EMAIL"] = address
    yield
  ensure
    original.nil? ? ENV.delete("ORGANISER_EMAIL") : ENV["ORGANISER_EMAIL"] = original
  end

  test "notification goes to ORGANISER_EMAIL when it is set" do
    with_organiser_email("organiser@example.test") do
      assert_equal [ "organiser@example.test" ], RsvpMailer.notification(@rsvp).to
    end
  end

  test "notification falls back to the event contact address when ORGANISER_EMAIL is unset" do
    with_organiser_email(nil) do
      assert_equal [ "hello@hyggerb.dk" ], RsvpMailer.notification(@rsvp).to
      # The literal above must be what the event config actually holds, or the
      # fallback is pinned to a value the app would never produce.
      assert_equal "hello@hyggerb.dk", EVENT.dig("contact", "hello")
    end
  end

  test "notification carries the details and seat count" do
    mail = RsvpMailer.notification(@rsvp)
    assert_equal "New hygge.rb RSVP: Ada", mail.subject
    assert_equal [ "ada@example.com" ], mail.reply_to
    assert_match "ada@example.com", mail.body.to_s
    assert_match "no nuts", mail.body.to_s
    assert_match "#{Rsvp.seats_taken} of #{Rsvp::CAPACITY}", mail.body.to_s
  end

  test "waitlisted confirmation says waitlist, not reserved" do
    waitlisted = Rsvp.create!(name: "Bo", email: "bo@example.com", waitlisted: true)
    mail = RsvpMailer.confirmation(waitlisted)
    assert_equal "You're on the hygge.rb waitlist", mail.subject
    assert_match "waitlist", mail.body.to_s
  end
end
