require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "renders the landing page" do
    get root_path
    assert_response :success
  end

  test "shows the wordmark in the header" do
    get root_path
    assert_select "header.site .brand", text: /hygge\.rb/
  end

  test "shows the Rails credit in the footer" do
    get root_path
    assert_select "footer.site .foot-bottom", text: /Made with Ruby on Rails/
  end
end
