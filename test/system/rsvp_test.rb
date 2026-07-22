require "application_system_test_case"

class RsvpTest < ApplicationSystemTestCase
  test "reserving a seat swaps the form for a confirmation" do
    visit root_path

    fill_in "Your name", with: "Ada Lovelace"
    fill_in "Email address", with: "ada@example.com"
    fill_in "Dietary needs or allergies", with: "no nuts"

    # Wait out the minimum-dwell spam check.
    sleep 3.5

    click_button "Reserve my seat"

    assert_text "Tak! Your seat is reserved."
    assert_no_selector "form.rsvp-form"
    assert_equal 1, Rsvp.count
  end

  test "an invalid email keeps the form and shows the error" do
    visit root_path

    fill_in "Your name", with: "Ada"
    fill_in "Email address", with: "not-an-email"
    sleep 3.5
    click_button "Reserve my seat"

    assert_selector "form.rsvp-form"
    assert_equal 0, Rsvp.count
  end
end
