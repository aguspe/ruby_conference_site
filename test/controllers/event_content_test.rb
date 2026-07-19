require "test_helper"

class EventContentTest < ActionDispatch::IntegrationTest
  test "EVENT is loaded and frozen" do
    assert EVENT.frozen?
    assert_equal 40, EVENT["capacity"]
  end

  test "hero shows the three facts" do
    get root_path
    assert_select ".facts .fact", count: 3
    assert_select ".fact dt", text: "When"
    assert_select ".hero .kicker .free", text: "Free"
  end

  test "hero headline is the plain wordmark" do
    get root_path
    assert_select ".hero h1", text: "hygge.rb"
  end

  test "sponsors lists Merkle and Dentsu plus a CTA" do
    get root_path
    assert_select ".spon .name", text: "Merkle"
    assert_select ".spon .name", text: "Dentsu"
    assert_select ".spon.cta a", text: /Become a sponsor/
  end
end
