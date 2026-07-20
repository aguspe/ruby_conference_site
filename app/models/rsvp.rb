class Rsvp < ApplicationRecord
  CAPACITY = EVENT["capacity"]

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
      rsvp.save
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
