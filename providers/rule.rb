require 'chef/mixin/shell_out'
include Chef::Mixin::ShellOut


action :append do
  updated = false
  if [:ipv4, :both].include?(new_resource.ip_version)
    updated |= handle_rule(new_resource, "ipv4")
  end
  if [:ipv6, :both].include?(new_resource.ip_version)
    if new_resource.table == 'nat' &&
        Gem::Version.new(/\d+(\.\d+(.\d+)?)?/.match(node['kernel']['release'])[0]) < Gem::Version.new('3.7')
      raise "NAT table cannot be used with IPv6 before Kernel 3.7"
    end
    updated |= handle_rule(new_resource, "ipv6")
  end
  new_resource.updated_by_last_action(updated)
end

def handle_rule(new_resource, ip_version)
  if new_resource.rule.kind_of?(String)
    rules = [new_resource.rule]
  elsif new_resource.rule.kind_of?(Array)
    rules = new_resource.rule
  else
    rules = ['']
  end
  if not node["simple_iptables"][ip_version]["chains"][new_resource.table].include?(new_resource.chain)
    node.normal["simple_iptables"][ip_version]["chains"][new_resource.table] = node["simple_iptables"][ip_version]["chains"][new_resource.table].dup << new_resource.chain unless ["PREROUTING", "INPUT", "FORWARD", "OUTPUT", "POSTROUTING"].include?(new_resource.chain)
    unless new_resource.chain == new_resource.direction || new_resource.direction == :none
      node.normal["simple_iptables"][ip_version]["rules"][new_resource.table] << {:rule => "-A #{new_resource.direction} #{new_resource.chain_condition} --jump #{new_resource.chain}", :weight => new_resource.weight}
    end
  end

  # Then apply the rules to the node
  updated = false
  rules.each do |rule|
    new_rule_string = rule_string(new_resource, rule, false)
    new_rule = {:rule => new_rule_string, :weight => new_resource.weight}
    table_rules = node.normal["simple_iptables"][ip_version]["rules"][new_resource.table]

    unless table_rules.include?(new_rule)
      table_rules << new_rule
      table_rules.sort! {|a,b| a[:weight] <=> b[:weight]}
      updated = true
      Chef::Log.debug("[#{ip_version}] added rule '#{new_rule_string}'")
    else
      Chef::Log.debug("[#{ip_version}] ignoring duplicate simple_iptables_rule '#{new_rule_string}'")
    end
  end
  return updated
end

def rule_string(new_resource, rule, include_table)
  jump = new_resource.jump ? "--jump #{new_resource.jump} " : ""
  table = include_table ? "--table #{new_resource.table} " : ""
  comment = %Q{ -m comment --comment "#{new_resource.comment || new_resource.name}" }
  rule = "#{table}-A #{new_resource.chain} #{jump}#{rule}#{comment}"
  rule
end

