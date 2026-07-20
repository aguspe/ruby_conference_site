class RsvpsController < ApplicationController
  include RsvpsHelper

  # `rate_limit` captures its store once, at class-definition time, so a test
  # cannot swap it by reassigning `Rails.cache`. This proxy resolves the cache
  # on every call instead, which keeps production on the configured store and
  # lets a test substitute a real store for the duration of one example.
  RATE_LIMIT_STORE = Object.new
  def RATE_LIMIT_STORE.increment(...) = Rails.cache.increment(...)

  rate_limit to: 5, within: 1.minute, only: :create,
             store: RATE_LIMIT_STORE, with: -> { render_confirmation }

  def create
    return render_confirmation if bot?

    @rsvp = Rsvp.reserve(
      name: rsvp_params[:name],
      email: rsvp_params[:email],
      dietary: rsvp_params[:dietary].presence
    )

    # `persisted?` must be checked before `waitlisted?`: at a full house an
    # invalid record still carries `waitlisted == true` from the model's
    # provisional flag, and must render the form-with-errors path.
    if @rsvp.persisted?
      @rsvp.waitlisted? ? render_full : render_confirmation
    else
      render_in_frame "rsvps/form", locals: { rsvp: @rsvp },
                      status: :unprocessable_entity
    end
  end

  private

  # Only ever called once `bot?` has confirmed `params[:rsvp]` is a hash, so
  # this can never raise ParameterMissing on a public endpoint.
  def rsvp_params
    params[:rsvp].permit(:name, :email, :dietary)
  end

  # Three silent filters: a honeypot field no human sees, a signed timestamp
  # that must be neither too fresh (minimum dwell) nor too old (replay), and a
  # structural check on the payload shape. All of them fall through to the
  # normal confirmation, so a bot — or someone probing with a malformed body —
  # learns nothing from the response.
  def bot?
    params[:company].present? ||
      !rsvp_shape_plausible? ||
      !rsvp_timestamp_fresh?(params[:t])
  end

  # The real form can only ever submit `rsvp` as a hash of scalar strings.
  # Anything else — a missing key, a bare string, an array, or a nested hash
  # where a field belongs — could not have come from a browser filling in this
  # form, so it is treated as bot traffic rather than as a validation failure.
  # Keeping it on the silent path also means `rsvp_params` never has to call
  # `require`, so a malformed body can't raise ParameterMissing.
  def rsvp_shape_plausible?
    raw = params[:rsvp]
    return false unless raw.is_a?(ActionController::Parameters)

    raw.to_unsafe_h.slice("name", "email", "dietary")
       .values.all? { |value| value.nil? || value.is_a?(String) }
  end

  def render_confirmation
    render_in_frame "rsvps/confirmation"
  end

  def render_full
    render_in_frame "rsvps/full"
  end

  def render_in_frame(partial, locals: {}, **options)
    render({ partial: "rsvps/frame",
             locals: { partial: partial, locals: locals } }.merge(options))
  end
end
