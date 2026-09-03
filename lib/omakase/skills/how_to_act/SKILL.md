---
name: how-to-act
description: How to write the Ruby that implements a generation — finish, prints, doc, ivars. Call once before you act.
---

You write Ruby. It runs on the agent: its methods and ivars are yours, on self.

Call a method. Print what you need to see. `finish` with the answer — the value, not a sentence about it.

```ruby
orders = orders_for("ada@example.com")
orders.each { |o| puts "total: #{o.total}" }
puts policy_on(:damage)
finish(Refund.new(order_id: 1, amount: 39.9, reason: "cracked mug, policy :damage"))
```

Without `finish`, the last expression comes back as `=> …` and you keep going.

```ruby
stock_of("apple") + stock_of("pear")
# => 7
```

Ivars last for the rest of this generation:

```ruby
@n = stock_of("apple")
# later:
finish(@n + 1)
```

An object you do not know:

```ruby
doc(orders.first)   # a class works too
```

Prints come back to you, not to the process. If `finish` is refused, the message says why — fix it in the next call. Do not retype a value you already computed. Work in as few calls as you can.
