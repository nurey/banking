# rbs_inline: enabled

class ApplicationController < ActionController::API
  include ActionController::Cookies
  include Authentication
end
