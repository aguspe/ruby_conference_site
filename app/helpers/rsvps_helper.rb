module RsvpsHelper
  MIN_DWELL = 3.seconds

  # An upper bound on the signed timestamp, so a captured `t` cannot be
  # replayed forever. 30 minutes is far more time than anyone needs for three
  # short fields, but long enough to survive a visitor who opens the page,
  # reads the schedule and the speaker list, and comes back to sign up. Past
  # that the signature stops verifying and the request is treated as a bot.
  MAX_DWELL = 30.minutes

  def rsvp_form_timestamp
    rsvp_verifier.generate(Time.current.to_i, expires_in: MAX_DWELL)
  end

  def rsvp_timestamp_fresh?(value)
    issued_at = rsvp_verifier.verify(value.to_s)
    Time.current.to_i - issued_at >= MIN_DWELL.to_i
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    false
  end

  private

  def rsvp_verifier
    ActiveSupport::MessageVerifier.new(
      Rails.application.secret_key_base, digest: "SHA256"
    )
  end
end
