module RsvpsHelper
  MIN_DWELL = 3.seconds

  def rsvp_form_timestamp
    rsvp_verifier.generate(Time.current.to_i)
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
