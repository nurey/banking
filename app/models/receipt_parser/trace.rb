# rbs_inline: enabled
# frozen_string_literal: true

module ReceiptParser
  module Trace
    # The step's name, the fields it changed (arrays as counts, scalars as
    # values), and any warnings it added.
    #
    # @rbs step: Class
    # @rbs before: Context
    # @rbs after: Context
    # @rbs return: Hash[Symbol, untyped]
    def self.entry(step, before, after)
      changed = (Context.members - Context::SHARED).each_with_object({}) do |field, fields|
        value = after.public_send(field)
        next if value == before.public_send(field)

        fields[field] = value.is_a?(Array) ? value.size : value
      end

      entry = { step: step.name.demodulize, changed: }
      added = after.warnings.drop(before.warnings.size)
      added.any? ? entry.merge(warnings: added) : entry
    end
  end
end
