# bench/delta/json_bench.cr
require "../bench_helper"

rnd     = Random.new(2024)
records = (1..5_000).map do |i|
  {"id" => i, "name" => "record #{i}", "tags" => ["t#{i % 7}", "t#{i % 11}"], "body" => "text #{i}"}
end
base = Delta::JSON.any({"records" => records, "log" => ""})

edited = Delta::JSON.copy(base)
edited["records"].as_a.each do |record|
  next unless rnd.rand < 0.05
  hash = record.as_h
  hash["body"] = JSON::Any.new(hash["body"].as_s + " edited")
  hash["name"] = JSON::Any.new("renamed")
end
inserted = Delta::JSON.copy(edited)
inserted["records"].as_a.insert(2_500, Delta::JSON.any({"id" => 0, "name" => "inserted"}))

ops     = Delta::JSON.diff(base, edited)
encoded = ops.to_json
wire    = Delta::JSON::Wire::Encoder.new.encode(ops)
STDOUT.puts "json doc: 5k records, 5% edited: #{ops.size} ops, #{encoded.bytesize} bytes plain, #{wire.bytesize} bytes wire"
STDOUT.puts "json doc: 5k records, 5% edited + 1 insert: #{Delta::JSON.diff(base, inserted).size} ops"

leaf_ops = (0...10_000).map do |i|
  i.even? ? Delta::JSON::Ops::Append.new(["log"] of Delta::JSON::Segment, "x").as(Delta::JSON::Op) : Delta::JSON::Ops::Set.new(["records", i % 5_000, "name"] of Delta::JSON::Segment, JSON::Any.new("n#{i}")).as(Delta::JSON::Op)
end

tracker = Delta::JSON::Tracker.new(base)
counter = 0

Benchmark.ips do |x|
  x.report("json diff 5k (in place edits)") { Delta::JSON.diff(base, edited) }
  x.report("json diff 5k (edits + insert)") { Delta::JSON.diff(base, inserted) }
  x.report("json apply_immutable 5k") { Delta::JSON.apply_immutable(base, ops) }
  x.report("json parse_ops") { Delta::JSON.parse_ops(encoded) }
  x.report("json to_json") { ops.to_json }
  x.report("json wire encode") { Delta::JSON::Wire::Encoder.new.encode(ops) }
  x.report("json wire decode") { Delta::JSON::Wire::Decoder.new.decode(wire) }
  x.report("json tracker change (1 leaf)") do
    counter += 1
    tracker.change { |draft| draft["records"][counter % 5_000]["name"] = "n#{counter}" }
  end
  x.report("json tracker change (100 appends)") do
    Delta::JSON::Tracker.new(base).change { |draft| 100.times { draft.append("log", "x") } }
  end
  x.report("json pending_ops 10k leaf ops") do
    pending = Delta::JSON::PendingOps.new
    pending.push(leaf_ops)
    pending.take(base)
  end
end
