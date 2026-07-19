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

  def self.seats_taken = confirmed.count
  def self.seats_left  = [CAPACITY - seats_taken, 0].max
  def self.full?       = seats_left.zero?

  # Creates a reservation, deciding confirmed-vs-waitlisted under a lock so two
  # simultaneous submissions can't both claim the last seat.
  #
  # Returns a persisted Rsvp on success, or an unpersisted one carrying errors.
  def self.reserve(name:, email:, dietary: nil)
    rsvp = new(name: name, email: email, dietary: dietary)
    return rsvp unless rsvp.valid?

    transaction do
      # Serialises concurrent reservations on a single advisory lock. Cheaper
      # than locking the table, and correct for the one row we're about to add.
      connection.execute("SELECT pg_advisory_xact_lock(#{LOCK_KEY})")
      rsvp.waitlisted = full?
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
end
