class RegistrationsController < Devise::RegistrationsController
	# Overriding Devise Registration from our requirement
  
	def new
    if user_signed_in?
      redirect_to dashboard_path
    else
      build_resource
      yield resource if block_given?
      respond_with resource
    end
  end

	def create
    build_resource(sign_up_params)
    if resource.save
        yield resource if block_given?
        if resource.active_for_authentication?
            set_flash_message :notice, :signed_up if is_flashing_format?
            sign_up(resource_name, resource)
            begin
             UserMailer.send_welcome_mail(resource).deliver_now
            rescue Exception => e
              p "xxxxx unable to send email #{e.inspect}"
            end
            begin 
              AdminMailer.send_new_registration_mail(resource).deliver_now
            rescue Exception => e
              p "xxxxx unable to send email #{e.inspect}"
            end  
            flash[:notice] = "Thanks for signing up. You’ve been sent an email to the address you signed up with. Follow the instructions to get started."
            redirect_to new_user_session_path
        else
            set_flash_message :notice, :"signed_up_but_#{resource.inactive_message}" if is_flashing_format?
            expire_data_after_sign_in!
            respond_with resource, location: after_inactive_sign_up_path_for(resource)
        end
    else
        clean_up_passwords resource
        resource.errors.full_messages.each {|x| flash[x] = x} # Rails 4 simple way
        redirect_to new_user_registration_path 
    end
	end

  private
  def sign_up_params
    params.require(:user).permit(:email, :password, :password_confirmation, :first_name, :last_name, :company, :role, :city, :country)
  end
end
