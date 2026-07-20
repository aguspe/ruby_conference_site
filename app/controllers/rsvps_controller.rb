class RsvpsController < ApplicationController
  include RsvpsHelper

  rate_limit to: 5, within: 1.minute, only: :create, with: -> { render_confirmation }

  def create
    return render_confirmation if bot?

    @rsvp = Rsvp.reserve(
      name: rsvp_params[:name],
      email: rsvp_params[:email],
      dietary: rsvp_params[:dietary].presence
    )

    if @rsvp.persisted?
      @rsvp.waitlisted? ? render_full : render_confirmation
    else
      render partial: "rsvps/form", locals: { rsvp: @rsvp },
             status: :unprocessable_entity
    end
  end

  private

  def rsvp_params
    params.require(:rsvp).permit(:name, :email, :dietary)
  end

  # Two silent filters: a honeypot field no human sees, and a minimum dwell
  # time. Both return the normal confirmation so a bot learns nothing.
  def bot?
    params[:company].present? || !rsvp_timestamp_fresh?(params[:t])
  end

  def render_confirmation
    render partial: "rsvps/confirmation"
  end

  def render_full
    render partial: "rsvps/full"
  end
end
