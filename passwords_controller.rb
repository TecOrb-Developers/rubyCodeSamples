class PasswordsController < Devise::PasswordsController
  # Overriding Devise password controller as per our requirement
  # POST /resource/password

  # Sending Forget password instructions over the provided email with secure devise encrypted token
  def create
    user = User.find_by_email(resource_params[:email])
    if user.approve_status != 'Rejected'
      self.resource = resource_class.send_reset_password_instructions(resource_params)
      yield resource if block_given?
      if successfully_sent?(resource)
        respond_with({}, location: after_sending_reset_password_instructions_path_for(resource_name))
      else
        flash[:notice]= resource.errors.full_messages.join(", ")
        respond_with({}, location: after_sending_reset_password_instructions_path_for(resource_name))
      end
    else
      flash[:notice]= "Sorry, we’ve had a few issues verifying your account. Please get in touch on +61 X XXXX XXXX or email XXXXXX@islandsystems.com."
      redirect_to new_user_session_path
    end
  end

  # Secure opening the edit password page 
  def edit
    unless params[:reset_password_token].present?
      flash[:notice]= "Password reset link has been expired"
      redirect_to new_user_session_path
    else
      self.resource = resource_class.new
      set_minimum_password_length
      resource.reset_password_token = params[:reset_password_token]
    end
    
  end
  
  # Updating password in case of forget password by using secure devise reset password token
  def update
    self.resource = resource_class.reset_password_by_token(resource_params)
    yield resource if block_given?
    if resource.errors.empty?
      resource.unlock_access! if unlockable?(resource)
      if Devise.sign_in_after_reset_password
        flash_message = resource.active_for_authentication? ? :updated : :updated_not_active
        set_flash_message!(:notice, flash_message)
        resource.after_database_authentication
        sign_in(resource_name, resource)
      else
        set_flash_message!(:notice, :updated_not_active)
      end
      respond_with resource, location: after_resetting_password_path_for(resource)
    else
      set_minimum_password_length
      flash[:notice]=resource.errors.full_messages.join(", ")
      respond_with resource, location: edit_user_password_path
    end
  end
end
