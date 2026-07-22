require "test_helper"

class SectionsTest < ActionDispatch::IntegrationTest
  setup { get root_path }

  test "cfp lists four criteria and the timeline" do
    assert_select ".cfp-crit li", count: 4
    assert_select ".timeline div", count: EVENT["cfp_timeline"].size
    assert_select ".timeline .key", count: 3
  end

  test "schedule lists every row and marks the DJ set" do
    assert_select ".sched tr", count: EVENT["schedule"].size
    assert_select ".sched tr.dj .ev", text: /DJ set/
    assert_select ".sched tr .t", text: "10:00"
  end

  test "venue shows the photo and the address" do
    assert_select ".venue-photo img[alt*=?]", "Åboulevarden"
    assert_select ".venue-meta dd", text: /8000 Aarhus C/
  end

  test "faq renders every question with the first one open" do
    assert_select "details.faq-item", count: EVENT["faq"].size
    assert_select "details.faq-item[open]", count: 1
  end
end
