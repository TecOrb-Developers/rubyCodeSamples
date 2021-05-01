class LiveChatChannel < ApplicationCable::Channel

  # calls when a client connects to the server
  def subscribed
    if params[:room_id].present?
      # creates a private chat room with a unique name
      stream_from("ChatRoom-#{(params[:room_id])}")
    end
  end
  
  # calls when a client broadcasts data
  def speak(data)

    sender    = get_sender(data)
    room_id   = data['room_id']
    message   = data['message']

    raise 'No room_id!' if room_id.blank?
    convo = get_convo(room_id) # A conversation is a room
    raise 'No conversation found!' if convo.blank?
    raise 'No message!' if message.blank?

    # adds the message sender to the conversation if not already included
    convo.users << sender unless convo.users.include?(sender)
    # saves the message and its data to the DB
    # Note: this does not broadcast to the clients yet!
    # This will be broadcast when this message will be save in model after callback
    Message.create!(
      conversation: convo,
      sender: sender,
      content: message
    )
  end

  def receive(data)
    payload = data
    roomId = 1
    ActionCable.server.broadcast("ChatRoom-#{(roomId)}", payload)
  end
  
  # Helpers
  
  def get_convo(room_code)
    Conversation.find_by(id: room_code)
  end
  
  def set_sender
    User.find_by(id: id)
  end
end