module StripeModule
	require "stripe"
	Stripe.api_key = ENV['TECORB_STRIPE_TEST_SECRET_KEY']
	# Create Stripe Customer
	# 
	# All of these methods will be use in whole applocation by include this model in required controllers
	# Here we are assuming, all of the exceptions are catching by using begin and rescue before calling methods in controllers.
	
	# Action to create customer at stripe using generated one time use source token from the card
	def createTecorbStripeCustomer user,stripeToken
		newCustomer = Stripe::Customer.create(
      :description => "Customer for email #{user.stripe_customer_email} with contact +#{user.country_code} #{user.contact}. Customer full name is #{user.full_name}",
      :email=> user.stripe_customer_email,
      :source => stripeToken # obtained with Stripe.js or ios/android Stripe SDKs who are using the payment apis
    )
    # Saving Stripe Customer Id in the database with related user's record
    user.update(stripe_customer_id: newCustomer["id"])
    return newCustomer
	end

	# Action is using to retrieve the customer object from the stripe by stripe_customer_id
	def retrieveCustomer stripeCustomerId
		Stripe::Customer.retrieve(stripeCustomerId)
	end

  # Action is using to Add a new Card in the customer record
	def add_card_on_stripe user,stripeToken
		stripeCustomerId = user.stripe_customer_id.present? ? user.stripe_customer_id : createTecorbStripeCustomer(user,stripeToken)
		customer = retrieveCustomer(stripeCustomerId)
		# Saving after checking if the customer is adding same same card again or first time
		card = checkDuplicateCard(stripeToken,customer,user)
		return card
	end

	# Action is using to add card at stripe
	def add_card_to_customer user,stripeToken
		is_saved = true
		begin
			customer_uid = user.stripe_customer_id
			if customer_uid.present? 
				# Stripe customer id found in the db
			  # Now retreving customer by this Id
			  customer = retrieveCustomer(customer_uid)
			  # Saving Card by checking the if it is not already saved
			  checkDuplicateCard(stripeToken,customer,user)
			  customer_uid = user.stripe_customer_id
			else
				# Stripe customer id not found, going to add new customer id
				customer_uid = createTecorbStripeCustomer(user,stripeToken)
			end
		rescue => e
			logger.info "xxxxxx Exception xxxxx --- #{e.message}"
			false
		end
	end
  
  # Checking if customer already has the same card or not
  def checkDuplicateCard source, customer, user
  	#Retrieve the card fingerprint using the stripe_card_token  
    newcard = Stripe::Token.retrieve(source)
    card_fingerprint = newcard.try(:card).try(:fingerprint) 
    card_exp_month = newcard.try(:card).try(:exp_month) 
    card_exp_year = newcard.try(:card).try(:exp_year) 
    card_stripe_id = newcard.try(:card).try(:id)
    card_last4 = newcard.try(:card).try(:last4)
    card_brand = newcard.try(:card).try(:brand)
    card_funding = newcard.try(:card).try(:funding)
    # check whether a card with that fingerprint already exists
    mainCard = customer.sources.all(:object => "card").data.select{|card| ((card.fingerprint==card_fingerprint)and(card.exp_month==card_exp_month)and(card.exp_year==card_exp_year))}.last 
    if !mainCard
      # Card is new, now going to add card
      mainCard = customer.sources.create(source: source)
    else
      # Card is already in the customer list
    end
    card = Card.save_card(user,mainCard,false)
    make_card_as_default(user,customer,card)

    #set the default card of the customer to be this card, as this is the last card provided by User and probably he want this card to be used for further transactions
    customer.default_card = mainCard.id 
    # saving the customer 
    customer.save 
  	# stripe card added to customer and now saving in our db.
  	user.update(stripe_customer_id: customer.id)
  	return card
  end

  # Action is fetching all saved cards list of user
	def list_customer_cards user,counts
		stripeCustomer = retrieveCustomer(user.stripe_customer_id)
		cards = stripeCustomer.sources.all(:limit => counts>1 ? 20 : 1, :object => "card")
		# This method will sync our database with updated cards with the user
		# Note: We are not saving the original card details at our database, We are saving secure Tokens provided by the stripe only
		# These secure tokens are using to get the card details or charging the customer etc.
		card = Card.syncWithTecorb(cards,user,stripeCustomer)
		counts>1 ? cards :  card
	end
  
  # Action to make a default card
	def make_card_as_default user,customer,card
		customer.default_source = card.stripe_id
		customer.save
		Card.updateDefaultCard(card,user)
	end

	# Action to remove card from stripe
	def removeStripeCard card
		stripeCustomer = Stripe::Customer.retrieve(card.user.stripe_customer_id)
		stripeCustomer.sources.retrieve(card.stripe_id).delete
		card.destroy
	end

end