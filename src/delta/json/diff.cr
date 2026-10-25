# src/delta/json/diff.cr
module Delta::JSON
  def self.diff(base : ::JSON::Any, value : ::JSON::Any) : Array(Op)
    ops = Array(Op).new
    diff_into(base, value, Path.new, ops)
    ops
  end

  protected def self.diff_into(base : ::JSON::Any, value : ::JSON::Any, path : Path, ops : Array(Op)) : Nil
    return if identical?(base, value)
    a = base.raw
    b = value.raw
    if a.is_a?(Hash(String, ::JSON::Any)) && b.is_a?(Hash(String, ::JSON::Any))
      diff_hash(a, b, path, ops)
    elsif a.is_a?(Array(::JSON::Any)) && b.is_a?(Array(::JSON::Any))
      diff_array(a, b, path, ops)
    elsif a.is_a?(String) && b.is_a?(String)
      diff_string(a, b, path, ops)
    elsif base != value
      ops << (path.empty? ? Ops::Replace.new(value) : Ops::Set.new(path, value))
    end
  end

  protected def self.diff_hash(a : Hash(String, ::JSON::Any), b : Hash(String, ::JSON::Any), path : Path, ops : Array(Op)) : Nil
    a.each_key do |key|
      ops << Ops::Delete.new(extend_path(path, key)) unless b.has_key?(key)
    end
    b.each do |key, child|
      if previous = a[key]?
        diff_into(previous, child, extend_path(path, key), ops)
      else
        ops << Ops::Set.new(extend_path(path, key), child)
      end
    end
  end

  protected def self.diff_array(a : Array(::JSON::Any), b : Array(::JSON::Any), path : Path, ops : Array(Op)) : Nil
    if a.size == b.size
      a.each_with_index { |child, index| diff_into(child, b[index], extend_path(path, index), ops) }
      return
    end
    limit = Math.min(a.size, b.size)
    prefix = 0
    while prefix < limit && same_value?(a[prefix], b[prefix])
      prefix += 1
    end
    suffix = 0
    while suffix < limit - prefix && same_value?(a[a.size - 1 - suffix], b[b.size - 1 - suffix])
      suffix += 1
    end
    ops << Ops::Splice.new(path.dup, prefix, a.size - prefix - suffix, b[prefix...(b.size - suffix)])
  end

  protected def self.diff_string(a : String, b : String, path : Path, ops : Array(Op)) : Nil
    return if a == b
    if b.bytesize > a.bytesize && b.starts_with?(a)
      ops << Ops::Append.new(path.dup, b.byte_slice(a.bytesize))
    elsif a.bytesize > b.bytesize && a.ends_with?(b)
      ops << Ops::Trim.new(path.dup, a.size - b.size)
    else
      ops << (path.empty? ? Ops::Replace.new(::JSON::Any.new(b)) : Ops::Set.new(path.dup, ::JSON::Any.new(b)))
    end
  end

  protected def self.same_value?(a : ::JSON::Any, b : ::JSON::Any) : Bool
    identical?(a, b) || a == b
  end

  protected def self.extend_path(path : Path, segment : Segment) : Path
    child = Path.new(path.size + 1)
    child.concat(path)
    child << segment
    child
  end
end
