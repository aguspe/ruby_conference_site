require "test_helper"

class RsvpsControllerTest < ActionDispatch::IntegrationTest
  # A timestamp old enough to pass the minimum-dwell check.
  def valid_timestamp
    ActiveSupport::MessageVerifier
      .new(Rails.application.secret_key_base, digest: "SHA256")
      .generate(10.seconds.ago.to_i)
  end

  def params(overrides = {})
    { rsvp: { name: "Ada", email: "ada@example.com", dietary: "" },
      company: "",
      t: valid_timestamp }.deep_merge(overrides)
  end

  test "a valid rsvp is stored and confirmed" do
    assert_difference "Rsvp.count", 1 do
      post rsvps_path, params: params
    end
    assert_response :success
    assert_match "Tak!", response.body
    assert_not Rsvp.last.waitlisted?
  end

  test "an invalid rsvp re-renders the form with errors and stores nothing" do
    assert_no_difference "Rsvp.count" do
      post rsvps_path, params: params(rsvp: { email: "nope" })
    end
    assert_response :unprocessable_entity
    assert_match "not a valid email address", response.body
  end

  test "a filled honeypot is silently discarded" do
    assert_no_difference "Rsvp.count" do
      post rsvps_path, params: params(company: "Spam Co")
    end
    assert_response :success
    assert_match "Tak!", response.body
  end

  test "a submission faster than the dwell threshold is discarded" do
    fresh = ActiveSupport::MessageVerifier
      .new(Rails.application.secret_key_base, digest: "SHA256")
      .generate(Time.current.to_i)

    assert_no_difference "Rsvp.count" do
      post rsvps_path, params: params(t: fresh)
    end
    assert_response :success
    assert_match "Tak!", response.body
  end

  test "a tampered timestamp is discarded" do
    assert_no_difference "Rsvp.count" do
      post rsvps_path, params: params(t: "forged")
    end
    assert_response :success
  end

  test "an rsvp past capacity is waitlisted" do
    Rsvp::CAPACITY.times { |i| Rsvp.reserve(name: "G#{i}", email: "g#{i}@example.com") }

    post rsvps_path, params: params
    assert_response :success
    assert Rsvp.last.waitlisted?
    assert_match "waitlist", response.body
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
end
