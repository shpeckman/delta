# bench/delta/msgpack_bench.cr
require "../bench_helper"
require "msgpack"

rnd = Random.new(2024)
records = Array(MessagePack::Type).new(5_000)
(1..5_000).each do |i|
  records << ({
    "id" => i.to_i64, "name" => "record #{i}", "tags" => ["t#{i % 7}", "t#{i % 11}"] of MessagePack::Type,
    "body" => "text #{i}",
  } of MessagePack::Type => MessagePack::Type).as(MessagePack::Type)
end
base = {"records" => records, "log" => ""} of MessagePack::Type => MessagePack::Type

edited = Delta::Msgpack.copy(base)
edited.as(Hash(MessagePack::Type, MessagePack::Type))["records"].as(Array(MessagePack::Type)).each do |record|
  next unless rnd.rand < 0.05
  hash = record.as(Hash(MessagePack::Type, MessagePack::Type))
  hash["body"] = hash["body"].as(String) + " edited"
  hash["name"] = "renamed"
end

ops = Delta::Msgpack.diff(base, edited)
bytes = Delta::Msgpack.pack_ops(ops)
puts "msgpack doc: 5k records, 5% edited: #{ops.size} ops, #{bytes.size} bytes"

Benchmark.ips do |x|
  x.report("msgpack diff 5k (in place edits)") { Delta::Msgpack.diff(base, edited) }
  x.report("msgpack apply_immutable 5k") { Delta::Msgpack.apply_immutable(base, ops) }
  x.report("msgpack pack_ops") { Delta::Msgpack.pack_ops(ops) }
  x.report("msgpack unpack_ops") { Delta::Msgpack.unpack_ops(bytes) }
end
