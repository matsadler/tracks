require File.expand_path("../../lib/tracks", __FILE__)
require File.expand_path("../test_helper", __FILE__)
require "test/unit"

class InputTest < Test::Unit::TestCase
  
  def setup
    @input = Tracks::Input.new(Proc.new do
      if chunk = @chunks.shift
        @input.recieve_chunk(chunk)
      else
        @input.finished = true
      end
    end)
  end
  
  def test_read_no_args
    @chunks = %W{foo bar baz}
    
    result = @input.read
    
    assert_equal("foobarbaz", result)
  end
  
  def test_read_with_length
    @chunks = %W{foo bar baz}
    
    result = @input.read(3)
    
    assert_equal("foo", result)
  end
  
  def test_read_with_length_longer_than_first_chunk
    @chunks = %W{foo bar baz}
    
    result = @input.read(4)
    
    assert_equal("foob", result)
  end
  
  def test_read_no_args_empty
    @chunks = []
    
    result = @input.read
    
    assert_equal("", result)
  end
  
  def test_read_with_length_empty
    @chunks = []
    
    result = @input.read(3)
    
    assert_equal(nil, result)
  end
  
  def test_read_with_length_past_end
    @chunks = %W{foo bar}
    
    result = @input.read(7)
    
    assert_equal("foobar", result)
  end
  
  def test_read_with_length_and_buffer
    @chunks = %W{foo bar baz}
    
    buffer = ""
    @input.read(3, buffer)
    
    assert_equal("foo", buffer)
  end
  
end