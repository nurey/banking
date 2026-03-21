# rbs_inline: enabled

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end
