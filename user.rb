class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :authentication_keys => [:contact,:country_code]

  # Model validation to take only numbers in the contact and country code(excluding+)
  validates :contact, :country_code, :format => { :with => /\A[0-9]*\z/ }
  # Model validation to unique contact for each user with country code
  validates :contact, uniqueness: { scope: :country_code }
  # Model validation to data presence
  validates :full_name, :contact, :country_code, presence: true
  # Require password only while creating the user
  validates :password, presence: true, :on=>:create
  
  # Associations with other models
  has_one :profile, dependent: :destroy
  has_many :cards,:dependent=>:destroy
  has_many :bank_accounts, :dependent=>:destroy
  # Direct association
  has_many :user_security_questions, :dependent=>:destroy
  # Indirect association using through
  has_many :security_questions, through: :user_security_questions
  has_many :payments, :dependent=>:destroy
  # Custom associations using custom foreign keys and models
  has_many :payees, :class_name => 'Payment',:foreign_key => 'payee_id',:dependent => :destroy
  has_many :devices,:dependent=>:destroy
  has_many :notifications, :dependent=>:destroy
  has_many :received_notifications, :class_name => 'Notification',:foreign_key => 'receiver_id',:dependent => :destroy
  has_many :referrals ,:dependent=>:destroy
  has_many :payouts,:dependent=>:destroy
  # Polymorphic
  has_many :pictures, as: :imageable
  belongs_to :community

  # Using Callbacks 
  before_create :ensure_authentication_token # i.e. api_key
  after_create :generate_account_reference
  after_destroy :destroy_cloudinary_qrcode,:destroy_stripe_account


  def as_json(options = {})
    super(options.merge({except: [:created_at,:updated_at,:approve_status,:full_contact,:stripe_customer_email,:stripe_customer_id,:stripe_customer_account_id,:referral,:business_admin_percentage],methods: [:admin_percentage,:service_fee]}))
  end

  def admin_percentage
    Api::ApiController.helpers.customer_percentage
  end

  def service_fee
    Api::ApiController.helpers.stripe_service_fee
  end

  def ensure_authentication_token
    self.api_key = generate_access_token
    self.last_active_at = Time.now
  end

  def generate_account_reference
    referenceKey = generate_access_token
    accountRef = "#{self.full_name.first(1)}#{referenceKey.last(3)}#{self.id}".upcase
    self.qr_image = generate_account_qrcode(accountRef,"account")
    self.account_reference = accountRef
    self.country_code = self.country_code.gsub('+','')
    self.stripe_customer_email = user_stripe_email(self)
    self.referral = "#{self.full_name.first(1)}#{self.id}#{referenceKey.first(5)}"
    self.save!
  end

  def generate_account_qrcode qrcodeData,folderName
    ApplicationController.helpers.generateAndUploadQRcodeAtCloudinary(qrcodeData,folderName)
  end

  def destroy_cloudinary_qrcode
    if self.qr_image.present? 
      imgname = self.qr_image.split("/").last.split('.').first      
      p "image name to be destroy #{imgname}"    
      ApplicationController.helpers.remove_image_from_cloudinary(imgname,"account")
    end
  end

  def destroy_stripe_account
    if self.stripe_customer_account_id.present?
      begin
        stripeAccount = self.stripe_customer_account_id
        account = Stripe::Account.retrieve(stripeAccount)
        account.account.destroy
        p "destroy#{account}"
      rescue Exception => e
        
      end
      
    end  
  end  

  private

  def user_stripe_email user
    "#{user.country_code}.#{user.contact}@tecorb.com"    
  end

  def generate_access_token
    loop do
    	# token = SecureRandom.base64.tr('+/=', 'Qrt')
      token = Devise.friendly_token
      break token unless User.where(api_key: token).first
    end
  end

  def transaction
    p self.loggedInUser
    a = Payment.where("user_id = ? or payee_id = ?" ,self.id,self.id).last
    p a
  end  


  def self.find_user id
    find_by_id(id)
  end

  
  def self.update_token user
    ltoken = '%06d' % Random.rand(100000..999999)
    stoken = '%06d' % Random.rand(100000..999999)
    user.update_attributes(:reset_password_token=>"#{stoken}t#{user.id}u#{(Time.now.to_i*379).to_s.reverse}#{ltoken}",:reset_password_sent_at=>Time.now)
  end

  def self.user_by_reset_password_token token
    find_by_reset_password_token(token)
  end

  def self.update_user_profile full_name,country_code,contact,image,user
    updated = user.update_attributes(full_name: full_name,country_code: country_code,contact: contact, image: image)
    updated ? {:code=>200,:result=>user} : {:code=>400,:result=>user.errors.full_messages.join(', ')}  
  end

  def self.update_one_by_one full_name,image,notify,user
    user.full_name = full_name if full_name.present?
    user.image = image if image.present?
    user.notify = ["true",true,1,"1"].include?(notify) if !notify.nil?
    user.save
  end

end
