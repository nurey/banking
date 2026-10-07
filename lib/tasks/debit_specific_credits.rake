namespace :debit_specific_credits do
  desc "Create debit-specific credits"
  task create: :environment do
    list = DoublyLinkedList.new
    CreditCardTransaction.without_credit.where("tx_date >= ?", "2020-01-01").order(id: :desc).each do |tx|
      list.push(tx)
    end

    list.each do |node|
      tx = node.data
      next unless tx.debit?

      puts "calling node.find on node data id #{tx.id}"
      credit_node = list.find_near(node) { |other_node| other_node.data.credit? && other_node.data.amount == tx.amount }
      if credit_node
        puts "found credit (#{credit_node.data}) for debit #{tx}"
        begin
          DebitSpecificCredit.create(debit_id: tx.id, credit_id: credit_node.data.id)
        rescue ActiveRecord::RecordNotUnique, PG::UniqueViolation
          puts "Failed to insert DebitSpecificCredit with debit_id #{tx.id} and credit_id #{credit_node.data.id}"
        end

        list.delete(credit_node)
      else
        puts "no credit found for debit #{tx}"
      end
    end
  end
end


class Node
  attr_accessor :data, :next, :prev

  def initialize(data)
    @data = data
    @next = nil
    @prev = nil
  end
end

class DoublyLinkedList
  attr_reader :length

  def initialize
    @head = nil
    @tail = nil
    @length = 0
  end

  def first
    @head
  end

  def last
    @tail
  end

  def push(data)
    node = Node.new(data)
    @head ||= node

    if @tail
      @tail.next = node
      node.prev = @tail
    end

    @tail = node
    @length += 1
    puts "Pushed #{data.id}"
    self
  end

  def find_near(node)
    # Check previous nodes (in the future relative to current node)
    curr_node = node.prev
    while curr_node
      return curr_node if yield(curr_node)
      curr_node = curr_node.prev
    end

    # Check next nodes up to 10 nodes ahead (in the past relative to current node)
    curr_node = node.next
    count = 1
    while curr_node && count < 10
      return curr_node if yield(curr_node)
      curr_node = curr_node.next
      count += 1
    end
  end

  def each
    _each { |node| yield(node) }
  end

  def delete(node)
    _unlink_node(node)
  end

  private

  def _each
    curr_node = @head
    while curr_node
      yield curr_node
      curr_node = curr_node.next
    end
  end

  def _unlink_node(node)
    @head = node.next if node.prev.nil?
    @tail = node.prev if node.next.nil?

    if node.prev.nil?
      node.next.prev = nil if node.next
    elsif node.next.nil?
      node.prev.next = nil if node.prev
    else
      node.prev.next, node.next.prev = node.next, node.prev
    end
    @length -= 1
  end
end
