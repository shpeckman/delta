# src/delta.cr
module Delta
  VERSION = {{ `shards version "#{__DIR__}/.."`.chomp.stringify }}
end
