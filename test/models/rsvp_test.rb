require "test_helper"

class RsvpTest < ActiveSupport::TestCase
  test "fixtures are empty so capacity tests start from a clean slate" do
    assert_equal 0, Rsvp.count
  end

  test "requires a name" do
    rsvp = Rsvp.new(email: "a@example.com")
    assert_not rsvp.valid?
    assert_includes rsvp.errors[:name], "can't be blank"
  end

  test "requires a well-formed email" do
    rsvp = Rsvp.new(name: "Ada", email: "not-an-email")
    assert_not rsvp.valid?
    assert_includes rsvp.errors[:email], "is not a valid email address"
  end

  test "email uniqueness ignores case" do
    Rsvp.create!(name: "Ada", email: "ada@example.com")
    dup = Rsvp.new(name: "Ada Again", email: "ADA@example.com")
    assert_not dup.valid?
    assert_includes dup.errors[:email], "has already reserved a seat"
  end

  test "normalises email to lowercase and strips whitespace" do
    rsvp = Rsvp.create!(name: "  Ada  ", email: "  ADA@Example.COM ")
    assert_equal "ada@example.com", rsvp.email
    assert_equal "Ada", rsvp.name
  end

  test "seats_left counts down from capacity" do
    assert_equal Rsvp::CAPACITY, Rsvp.seats_left
    Rsvp.reserve(name: "Ada", email: "ada@example.com")
    assert_equal Rsvp::CAPACITY - 1, Rsvp.seats_left
  end

  test "the last seat is confirmed and the next is waitlisted" do
    (Rsvp::CAPACITY - 1).times do |i|
      Rsvp.reserve(name: "Guest #{i}", email: "guest#{i}@example.com")
    end

    last = Rsvp.reserve(name: "Last", email: "last@example.com")
    assert last.persisted?
    assert_not last.waitlisted?
    assert_equal 0, Rsvp.seats_left
    assert Rsvp.full?

    overflow = Rsvp.reserve(name: "Overflow", email: "overflow@example.com")
    assert overflow.persisted?
    assert overflow.waitlisted?
  end

  test "waitlisted records do not consume seats" do
    Rsvp.create!(name: "W", email: "w@example.com", waitlisted: true)
    assert_equal Rsvp::CAPACITY, Rsvp.seats_left
  end

  test "reserve returns an unpersisted record with errors when invalid" do
    rsvp = Rsvp.reserve(name: "", email: "nope")
    assert_not rsvp.persisted?
    assert rsvp.errors.any?
  end

  test "create! cannot overfill the room past capacity" do
    Rsvp::CAPACITY.times do |i|
      Rsvp.reserve(name: "Guest #{i}", email: "guest#{i}@example.com")
    end
    assert_equal Rsvp::CAPACITY, Rsvp.confirmed.count

    assert_raises(ActiveRecord::RecordInvalid) do
      Rsvp.create!(name: "Sneaky", email: "sneaky@example.com", waitlisted: false)
    end
    assert_equal Rsvp::CAPACITY, Rsvp.confirmed.count
  end

  test "a waitlisted record cannot be flipped to confirmed past capacity" do
    Rsvp::CAPACITY.times do |i|
      Rsvp.reserve(name: "Guest #{i}", email: "guest#{i}@example.com")
    end
    overflow = Rsvp.reserve(name: "Overflow", email: "overflow@example.com")
    assert overflow.waitlisted?

    assert_raises(ActiveRecord::RecordInvalid) { overflow.update!(waitlisted: false) }
    assert overflow.reload.waitlisted?, "record should still be waitlisted"
    assert_equal Rsvp::CAPACITY, Rsvp.confirmed.count
  end

  test "a waitlisted record can be promoted when a seat frees up" do
    Rsvp::CAPACITY.times do |i|
      Rsvp.reserve(name: "Guest #{i}", email: "guest#{i}@example.com")
    end
    overflow = Rsvp.reserve(name: "Overflow", email: "overflow@example.com")
    Rsvp.confirmed.first.destroy!

    assert overflow.update(waitlisted: false), overflow.errors.full_messages.to_sentence
    assert_equal Rsvp::CAPACITY, Rsvp.confirmed.count
  end

  test "capacity validation does not affect waitlisted records" do
    Rsvp::CAPACITY.times do |i|
      Rsvp.reserve(name: "Guest #{i}", email: "guest#{i}@example.com")
    end

    extra = Rsvp.create!(name: "W", email: "w@example.com", waitlisted: true)
    assert extra.persisted?
    assert_equal Rsvp::CAPACITY, Rsvp.confirmed.count
  end
end

# Genuine concurrency test: two real OS threads, each with its own DB
# connection, racing to reserve the last remaining seat.
#
# This class turns OFF transactional fixtures (`use_transactional_tests =
# false`). Rails' default transactional-test wrapper runs each test inside a
# single open transaction on ONE connection, then rolls it back; a second
# thread checking out a second connection from the pool would never see
# uncommitted rows written by the first, and any rows the second thread
# commits would survive the rollback of the first's transaction while the
# first thread's own writes vanish. That combination makes the two threads
# blind to each other's state and leaves debris behind — it cannot exercise
# real contention. Running without transactional fixtures means every write
# really commits, so the two threads genuinely contend for the same row and
# the same Postgres advisory lock, and we manually clean up afterward.
#
# It also widens the race window on purpose. Local Postgres over a Unix socket
# is fast enough that the read-decide-write window in `reserve` closes in
# microseconds: with the bare code both threads finish before the other is
# scheduled, and the test passes even when the advisory lock is deleted, i.e.
# it would demonstrate the behaviour without guarding it. So the test installs
# `Rsvp.race_window_hook` — a no-op in production — which `reserve` calls
# between reading the seat count and saving. With a 50ms sleep in that window
# both threads are guaranteed to read the seat count before either writes, so
# an unserialised `reserve` reliably double-books the last seat and this test
# reliably fails. Verified 5/5 green with the lock, 5/5 red without it.
class RsvpConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  # Wide enough to guarantee interleaving, small enough to stay cheap.
  RACE_WINDOW = 0.05

  teardown do
    Rsvp.race_window_hook = nil
    Rsvp.delete_all
  end

  test "two simultaneous reservations for the last seat: exactly one is confirmed" do
    assert_equal 0, Rsvp.count, "expected a clean table before seeding the boundary"

    (Rsvp::CAPACITY - 1).times do |i|
      Rsvp.reserve(name: "Guest #{i}", email: "conc-guest#{i}@example.com")
    end
    assert_equal 1, Rsvp.seats_left, "boundary setup should leave exactly one seat"

    # Widen the race window only for the two racers, not the 39 seeding writes.
    Rsvp.race_window_hook = -> { sleep RACE_WINDOW }

    barrier = Concurrent::CyclicBarrier.new(2)
    results = Concurrent::Array.new

    threads = [
      Thread.new do
        barrier.wait
        results << Rsvp.reserve(name: "Racer A", email: "conc-racer-a@example.com")
      end,
      Thread.new do
        barrier.wait
        results << Rsvp.reserve(name: "Racer B", email: "conc-racer-b@example.com")
      end
    ]
    threads.each(&:join)

    ActiveRecord::Base.connection_handler.clear_active_connections!

    assert_equal 2, results.size
    confirmed = results.reject(&:waitlisted?)
    waitlisted = results.select(&:waitlisted?)

    assert_equal 1, confirmed.size, "exactly one racer should win the last seat"
    assert_equal 1, waitlisted.size, "exactly one racer should be waitlisted"
    assert_equal Rsvp::CAPACITY, Rsvp.confirmed.count, "confirmed rows must never exceed capacity"
  end
end
