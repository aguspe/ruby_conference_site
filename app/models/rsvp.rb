class Rsvp < ApplicationRecord
  CAPACITY = EVENT["capacity"]

  # The seat cap bounds confirmed seats but says nothing about rows. Without a
  # second bound the waitlist grows without limit, and since every accepted row
  # sends two emails (attendee + organiser), unbounded rows means unbounded mail
  # to caller-supplied addresses from the conference's own sending domain.
  #
  # Half the room is a deliberately generous ceiling: for a free ~40-seat event,
  # 20 people waiting is already more than any realistic run of cancellations
  # could ever absorb, so the bound cannot plausibly turn away someone who would
  # have got a seat. It caps total rows at 60 and total mail at 120.
  WAITLIST_CAPACITY = CAPACITY / 2

  # Raised as a base error on the unpersisted record `reserve` returns when the
  # waitlist is full. The controller keys its "waitlist is full" response off
  # this, so it lives here rather than being matched by string in two places.
  WAITLIST_FULL_ERROR = "the waitlist is full; we can't take any more names"

  normalizes :email, with: ->(email) { email.to_s.strip.downcase }
  normalizes :name,  with: ->(name) { name.to_s.strip }

  validates :name, presence: true
  validates :email,
    presence: true,
    format: { with: URI::MailTo::EMAIL_REGEXP, message: "is not a valid email address" },
    uniqueness: { case_sensitive: false, message: "has already reserved a seat" }

  scope :confirmed,  -> { where(waitlisted: false) }
  scope :waitlisted, -> { where(waitlisted: true) }

  validate :confirmed_seat_must_be_available

  # Test-only seam. `reserve` calls this between reading the seat count and
  # writing the row — exactly the window an unserialised reservation would
  # race in. In production it is nil and costs a single nil check; the
  # concurrency test replaces it with a short sleep so the race is wide enough
  # to be observed deterministically rather than left to scheduler luck.
  class_attribute :race_window_hook, instance_accessor: false, default: nil

  def self.seats_taken = confirmed.count
  def self.seats_left  = [CAPACITY - seats_taken, 0].max
  def self.full?       = seats_left.zero?

  def self.waitlist_taken = waitlisted.count
  def self.waitlist_full? = waitlist_taken >= WAITLIST_CAPACITY

  # True for the unpersisted record `reserve` returns when it refused to add
  # another name to a full waitlist — as opposed to an ordinary validation
  # failure, which must still render the form with its errors.
  def waitlist_rejected? = errors[:base].include?(WAITLIST_FULL_ERROR)

  # Creates a reservation, deciding confirmed-vs-waitlisted under a lock so two
  # simultaneous submissions can't both claim the last seat.
  #
  # Returns a persisted Rsvp on success, or an unpersisted one carrying errors.
  def self.reserve(name:, email:, dietary: nil)
    rsvp = new(name: name, email: email, dietary: dietary)
    # Provisional; the authoritative decision is made under the lock below.
    # Set before this first `valid?` so the capacity validation sees the same
    # waitlisted flag the row would actually be saved with — otherwise a full
    # house would reject the record here instead of waitlisting it.
    rsvp.waitlisted = full?
    return rsvp unless rsvp.valid?

    transaction do
      # Serialises concurrent reservations on a single advisory lock. Cheaper
      # than locking the table, and correct for the one row we're about to add.
      connection.execute("SELECT pg_advisory_xact_lock(#{LOCK_KEY})")
      rsvp.waitlisted = full?
      race_window_hook&.call

      # Checked under the same lock as the seat decision, so two simultaneous
      # submissions can't both claim the last waitlist place. `valid?` has
      # already passed above, so this is the only error the record can carry —
      # which is what lets `waitlist_rejected?` be an unambiguous predicate.
      if rsvp.waitlisted? && waitlist_full?
        rsvp.errors.add(:base, WAITLIST_FULL_ERROR)
      else
        rsvp.save
      end
    end

    rsvp
  rescue ActiveRecord::RecordNotUnique
    # Lost a race against a duplicate email; surface it as a validation error.
    rsvp.errors.add(:email, "has already reserved a seat")
    rsvp
  end

  # Arbitrary constant identifying the reservation lock in Postgres.
  LOCK_KEY = 4_242_026

  private

  # Structural backstop against accidentally overfilling the room through any
  # path other than `reserve` — a bare `create!`, or flipping a waitlisted row
  # to confirmed with `update!(waitlisted: false)`.
  #
  # Division of responsibility: this validation is NOT a concurrency guard. It
  # reads a count that two simultaneous transactions can both see as under
  # capacity, so on its own it can still be raced past. The `pg_advisory_xact_lock`
  # in `reserve` is what makes the check race-safe, by serialising the
  # read-decide-write window. The validation only catches honest mistakes in
  # code that never took the lock in the first place.
  def confirmed_seat_must_be_available
    return if waitlisted?

    already_confirmed = self.class.confirmed.where.not(id: id).count
    return if already_confirmed < CAPACITY

    errors.add(:base, "the conference is at capacity; no confirmed seats remain")
  end
end
