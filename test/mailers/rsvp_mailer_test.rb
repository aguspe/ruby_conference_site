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

  test "notification goes to the organiser with the details and seat count" do
    mail = RsvpMailer.notification(@rsvp)
    assert_equal [ ENV.fetch("ORGANISER_EMAIL", "hello@hyggerb.dk") ], mail.to
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
