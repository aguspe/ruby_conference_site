require "test_helper"

class Admin::RsvpsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_admin_user = ENV["ADMIN_USER"]
    @original_admin_password = ENV["ADMIN_PASSWORD"]
    ENV["ADMIN_USER"] = "organiser"
    ENV["ADMIN_PASSWORD"] = "hygge"
    Rsvp.create!(name: "Ada", email: "ada@example.com", dietary: "no nuts")
  end

  teardown do
    ENV["ADMIN_USER"] = @original_admin_user
    ENV["ADMIN_PASSWORD"] = @original_admin_password
  end

  def auth_headers(user = "organiser", password = "hygge")
    { "HTTP_AUTHORIZATION" =>
        ActionController::HttpAuthentication::Basic.encode_credentials(user, password) }
  end

  test "requires credentials" do
    get admin_rsvps_path
    assert_response :unauthorized
  end

  test "rejects wrong credentials" do
    get admin_rsvps_path, headers: auth_headers("organiser", "wrong")
    assert_response :unauthorized
  end

  test "lists rsvps with the seat count" do
    get admin_rsvps_path, headers: auth_headers
    assert_response :success
    assert_match "ada@example.com", response.body
    assert_match "no nuts", response.body
    assert_match "1 / #{Rsvp::CAPACITY}", response.body
  end

  test "exports csv" do
    get admin_rsvps_path(format: :csv), headers: auth_headers
    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match "name,email,dietary,waitlisted,created_at", response.body
    assert_match "Ada,ada@example.com,no nuts,false", response.body
  end

  test "rejects unauthenticated csv requests" do
    get admin_rsvps_path(format: :csv)
    assert_response :unauthorized
  end

  test "fails closed when ADMIN_USER is unset" do
    ENV["ADMIN_USER"] = nil
    get admin_rsvps_path, headers: auth_headers
    assert_response :unauthorized
  end

  test "fails closed when ADMIN_USER is blank" do
    ENV["ADMIN_USER"] = ""
    get admin_rsvps_path, headers: auth_headers
    assert_response :unauthorized
  end

  test "fails closed when ADMIN_PASSWORD is unset" do
    ENV["ADMIN_PASSWORD"] = nil
    get admin_rsvps_path, headers: auth_headers
    assert_response :unauthorized
  end

  test "fails closed when ADMIN_PASSWORD is blank" do
    ENV["ADMIN_PASSWORD"] = ""
    get admin_rsvps_path, headers: auth_headers
    assert_response :unauthorized
  end

  test "fails closed when both credentials are unset, even with empty submitted credentials" do
    ENV["ADMIN_USER"] = nil
    ENV["ADMIN_PASSWORD"] = nil
    get admin_rsvps_path, headers: auth_headers("", "")
    assert_response :unauthorized
  end

  test "rejects a wrong-length username without erroring" do
    get admin_rsvps_path, headers: auth_headers("org", "hygge")
    assert_response :unauthorized
  end

  test "rejects a wrong-length password without erroring" do
    get admin_rsvps_path, headers: auth_headers("organiser", "wrong-length-password")
    assert_response :unauthorized
  end

  test "neutralises leading formula characters in csv fields to prevent csv injection" do
    Rsvp.create!(name: "=cmd|'/c calc'!A1", email: "formula@example.com", dietary: "+SUM(1+1)")

    get admin_rsvps_path(format: :csv), headers: auth_headers

    assert_response :success
    refute_match(/,=cmd/, response.body)
    refute_match(/,\+SUM/, response.body)
    assert_match "'=cmd", response.body
    assert_match "'+SUM", response.body
  end
end
