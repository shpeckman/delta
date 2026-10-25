# src/delta/json/errors.cr
module Delta::JSON::Errors
  class Error < Exception
  end

  class InvalidPath < Error
  end

  class InvalidValue < Error
  end

  class InvalidOp < Error
  end

  class Stale < Error
  end

  class Settled < Error
  end

  class Rejected < Error
  end

  class Closed < Error
  end
end
