#
# Cookbook Name:: gdash
# Recipe:: default
#
# Copyright 2012, Sean Escriva <sean.escriva@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
include_recipe "build-essential"
include_recipe "unicorn"

node.gdash.packages.each do |pkg|
    package pkg
end

gem_package "bundler"

remote_file node.gdash.tarfile do
  mode "00666"
  owner node.gdash.owner
  group node.gdash.group
  source node.gdash.url
  action :create_if_missing
end

directory node.gdash.base do
  owner node.gdash.owner
  group node.gdash.group
end

directory File.join(node.gdash.base, "templates") do
  owner node.gdash.owner
  group node.gdash.group
end

execute "bundle" do
  command "bundle install --binstubs #{File.join(node.gdash.base, 'bin')} --path #{File.join(node.gdash.base, 'vendor', 'bundle')}"
  user node.gdash.owner
  group node.gdash.group
  cwd node.gdash.base
  creates File.join(node.gdash.base, "bin")
  action :nothing
end

ruby_block "bundle_unicorn" do
  block do
    gemfile = Chef::Util::FileEdit.new(
      File.join(node.gdash.base, 'Gemfile')
    )
    gemfile.insert_line_if_no_match(/unicorn/, 'gem "unicorn"')
    gemfile.write_file
  end
  notifies :run, resources(:execute => "bundle"), :immediately
  not_if do
    File.exists?(File.join(node.gdash.base, 'Gemfile')) &&
    File.read(File.join(node.gdash.base, 'Gemfile')).include?('unicorn')
  end
  action :nothing
end

directory File.join(node.gdash.base, 'graph_templates', 'dashboards') do
  action :nothing
  recursive true
end

execute "gdash: untar" do
  command "tar zxf #{node.gdash.tarfile} -C #{node.gdash.base} --strip-components=1"
  creates File.join(node.gdash.base, "Gemfile.lock")
  user node.gdash.owner
  group node.gdash.group
  notifies :create, resources(:ruby_block => "bundle_unicorn"), :immediately
  notifies :delete, resources(:directory => File.join(node.gdash.base, 'graph_templates', 'dashboards')), :immediately
end

template File.join(node.gdash.base, "config", "gdash.yaml") do
  owner node.gdash.owner
  group node.gdash.group
  notifies :restart, "service[gdash]"
end

unicorn_config '/etc/unicorn/gdash.app' do
  listen "#{node[:gdash][:interface]}:#{node[:gdash][:port]}" => {:backlog => 100}
  working_directory node.gdash.base
  worker_timeout 60
  preload_app false
  worker_processes 2
  owner 'root'
  group 'root'
  pid "#{node.gdash.base}/gdash.pid"
end

case node[:platform_family] 
  when "debian"
    runit_service "gdash"
  when "rhel"
    template "/etc/init.d/gdash" do
      source "gdash_init.erb"
      owner "root"
      group "root"
      mode 00755
    end
    service "gdash" do
      action [ :enable, :start ]
    end
end
