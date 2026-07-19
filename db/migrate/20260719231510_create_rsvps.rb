class CreateRsvps < ActiveRecord::Migration[8.1]
  def change
    create_table :rsvps do |t|
      t.string  :name,       null: false
      t.string  :email,      null: false
      t.text    :dietary
      t.boolean :waitlisted, null: false, default: false

      t.timestamps
    end

    add_index :rsvps, "lower(email)", unique: true, name: "index_rsvps_on_lower_email"
    add_index :rsvps, :waitlisted
  end
end
