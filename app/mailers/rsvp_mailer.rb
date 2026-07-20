class RsvpMailer < ApplicationMailer
  default from: -> { "hygge.rb <#{EVENT.dig("contact", "hello")}>" }

  def confirmation(rsvp)
    @rsvp = rsvp
    subject = if rsvp.waitlisted?
      "You're on the hygge.rb waitlist"
    else
      "Your seat at hygge.rb is reserved"
    end

    mail to: rsvp.email, subject: subject
  end

  def notification(rsvp)
    @rsvp = rsvp
    @seats_taken = Rsvp.seats_taken

    mail to: ENV.fetch("ORGANISER_EMAIL", EVENT.dig("contact", "hello")),
         subject: "New hygge.rb RSVP: #{rsvp.name}",
         reply_to: rsvp.email
  end
end
