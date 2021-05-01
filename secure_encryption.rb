require 'openssl'
require 'base64'

# We are using base64 encryption for the tokens

module SecureEncryption
  def self.included(base)
    base.extend self
  end

  def cipher
    # Here we are using Advanced Encryption Standard (AES)
    # Creating AES object
    OpenSSL::Cipher.new('aes-256-cbc') 
  end

  def cipher_key
    # This is our cipher key, it needs to be change in between to more secure the applicaion
    # If we will save these encrypted tokens we need to save their cipher keys at very securely
    'jai@tecorb!@21##@'
  end

  # Action is using to encode the token using provided cipher key
  def encode_token(value)
    c = cipher.encrypt
    c.key = Digest::SHA256.digest(cipher_key)
    Base64.strict_encode64(c.update(value.to_s) + c.final)
  end

  # Action to decode the encrypted token to it's original value using the same cipher key from which it was generated
  def decode_token(value)
    begin
      c = cipher.decrypt
      c.key = Digest::SHA256.digest(cipher_key)
      c.update(Base64.strict_decode64(value.to_s)) + c.final
    rescue Exception=> e
      false
    end
  end
end