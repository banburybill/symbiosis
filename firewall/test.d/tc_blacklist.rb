$: << "../lib/"
require 'symbiosis/firewall/blacklist'
require 'test/unit'
require 'pp'

class TestBlacklist < Test::Unit::TestCase

  include Symbiosis::Firewall

  def setup
    @db = "test_blacklist.db"
  end

  def teardown
   File.unlink(@db) if File.exist?(@db)
  end

  def test_me
    bl = Blacklist.new
    bl.logtail_db = @db
    bl.base_dir = "."
    results = bl.generate

    # TODO test the output!
    pp results if $VERBOSE
  end
  
end







