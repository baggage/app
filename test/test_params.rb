require_relative 'helper'

class ParamsTest < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    Baggage::App
  end

  def test_params
    %w[ stats update unsubscribe ].each do |call|
        s = Baggage::Subscriber.new
        s.subscribe(:email => 'user@domain.com')
        get "/#{call}/gggg?token=#{s.doc[:admin_token]}"
        expected = 'Invalid Parameter: id'
        assert_equal expected, last_response.body
        assert_equal false, last_response.ok?

        s = Baggage::Subscriber.new
        s.subscribe(:email => 'user@domain.com')
        get "/#{call}/#{s.id}?token=gggg"
        expected = 'Invalid Parameter: token'
        assert_equal expected, last_response.body
        assert_equal false, last_response.ok?

        s = Baggage::Subscriber.new
        s.subscribe(:email => 'user@domain.com')
        get "/#{call}/#{'a' * Baggage::ID_LENGTH}?token=#{s.doc[:admin_token]}"
        assert_match /could not read/, last_response.body
        assert_equal false, last_response.ok?

        s = Baggage::Subscriber.new
        s.subscribe(:email => 'user@domain.com')
        get "/#{call}/#{s.id}?token=#{'a' * Baggage::TOKEN_LENGTH}"
        assert_match /invalid token/, last_response.body
        assert_equal false, last_response.ok?
    end
  end

end
