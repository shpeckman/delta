# src/delta/json/value.cr
module Delta::JSON
  alias Container = Hash(String, ::JSON::Any) | Array(::JSON::Any)
  alias Segment = String | Int32
  alias Path = Array(Segment)

  def self.any(value : ::JSON::Any) : ::JSON::Any
    copy(value)
  end

  def self.any(value : String) : ::JSON::Any
    ::JSON::Any.new(value)
  end

  def self.any(value : Bool) : ::JSON::Any
    ::JSON::Any.new(value)
  end

  def self.any(value : Nil) : ::JSON::Any
    ::JSON::Any.new(nil)
  end

  def self.any(value : Int) : ::JSON::Any
    ::JSON::Any.new(value.to_i64)
  end

  def self.any(value : Float) : ::JSON::Any
    float = value.to_f64
    raise Errors::InvalidValue.new("non-finite number: #{float}") unless float.finite?
    ::JSON::Any.new(float)
  end

  def self.any(value) : ::JSON::Any
    copy(::JSON.parse(value.to_json))
  end

  def self.copy(value : ::JSON::Any) : ::JSON::Any
    case raw = value.raw
    when Hash(String, ::JSON::Any)
      hash = Hash(String, ::JSON::Any).new(initial_capacity: raw.size)
      raw.each { |key, child| hash[key] = copy(child) }
      ::JSON::Any.new(hash)
    when Array(::JSON::Any)
      ::JSON::Any.new(raw.map { |child| copy(child) })
    when Float64
      raise Errors::InvalidValue.new("non-finite number: #{raw}") unless raw.finite?
      value
    else
      value
    end
  end

  def self.container?(value : ::JSON::Any) : Bool
    raw = value.raw
    raw.is_a?(Hash(String, ::JSON::Any)) || raw.is_a?(Array(::JSON::Any))
  end

  def self.identical?(left : ::JSON::Any, right : ::JSON::Any) : Bool
    a = left.raw
    b = right.raw
    case a
    when Hash(String, ::JSON::Any)
      b.is_a?(Hash(String, ::JSON::Any)) && a.same?(b)
    when Array(::JSON::Any)
      b.is_a?(Array(::JSON::Any)) && a.same?(b)
    else
      false
    end
  end

  def self.format(path : Path) : String
    return "/" if path.empty?
    String.build do |io|
      path.each do |segment|
        io << '/'
        io << segment
      end
    end
  end
end
