namespace :db do
  desc 'backup the database'
  task backup: :environment do
    db = ActiveRecord::Base.connection.current_database
    destination = Rails.root.join("db/#{db}.dump")
    `pg_dump -d #{db} -Fc > #{destination}`
    puts "Dumped to #{destination}"
  end
end
