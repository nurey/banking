namespace :receipts do
  desc "Re-parse receipts parsed by an older parser, or one receipt by id or capture_id (FORCE=1 for a confirmed one)"
  task :reparse, [ :receipt ] => :environment do |_task, args|
    if args[:receipt]
      key = args[:receipt]
      receipt = key.match?(/\A\d+\z/) ? Receipt.find(key) : Receipt.find_by!(capture_id: key)
      outcome = receipt.reparse!(force: ENV["FORCE"] == "1")
      puts "#{receipt.id} #{receipt.capture_id}: #{outcome}"
      puts "  confirmed; set FORCE=1 to rewrite only its `parsed` output" if outcome == :skipped
    else
      outcomes = Receipt.needing_reparse.find_each.map { it.reparse! }
      puts "Re-parsed #{outcomes.size} receipt(s) with parser v#{ReceiptParser::VERSION}: #{outcomes.tally}"
    end
  end

  desc "Score the parser on ocr-bench output: DIR holds <name>.<variant>.ocr.json and <name>.expected.json"
  task bench: :environment do
    abort "receipts:bench is for development" unless Rails.env.local?
    dir = ENV.fetch("DIR") { abort "Set DIR to the corpus directory" }
    puts ReceiptBench.new(dir).run
  end
end
