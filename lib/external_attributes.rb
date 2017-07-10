require "external_attributes/version"

module ExternalAttributes
	#
	# MODULE CREATED BY CODEPHONIC/CODEEV FOR ATTRIBUTES WITH EXTERNAL TABLE
	# This module creates custom ActiveRecord attributes
	# with external meta database with key and value
	#
	# Additional methods:
	# object.attribute - get value of the attribute
	# object.attribute= - set value pf the attribute
	# object.attribute_changed? -0 check if attribute was change after save
	#
	
	def external_attributes_for ( association, *args, key: :key, value: :value )
		class_eval do
			
			define_method("initialize") do |*options|
				super *options
				if !options.empty? and !(options.last.try(:keys) - (options.last.try(:keys) - args)).empty?
					args.each do |attribute|
						self.instance_variable_set("@#{attribute}", options.last[attribute]) if options.last[attribute]
					end
				end
			end
			
			##################
			# external_where #
			##################
			define_singleton_method :external_where do |*where_args|
				where_args = where_args.last
				mds = Array.new
				where_args.each do |k,v|
					mds << association.to_s.classify.safe_constantize.where(key => k, value => v).select("#{self.table_name.singularize}_id").map{|md| md.send("#{self.table_name.singularize}_id".to_sym)}
				end
				ids = mds.shift
				mds.each do |arr|
					ids = ids & arr
				end
				return self.where(id: ids) unless ids.empty?
				self.where("1=0")
			end
			
			##################
			# external_order #
			##################
			define_singleton_method :external_order do |*order_args|
				orders = Array.new
				return_query = self
				order_args.each do |arg|
					if arg.is_a? Hash
						arg.each do |k, v|
							if k.to_sym.in?(args)
								orders << "#{k}_table.#{value} #{v}"
								return_query = return_query.joins("LEFT JOIN #{association} as #{k}_table ON #{self.table_name}.id = #{k}_table.#{self.table_name.singularize}_id AND #{k}_table.#{key} = '#{k}'")
							else
							  orders << "#{k} #{v}"
							end
						end
					else
						if arg.to_sym.in?(args)
							orders << "#{arg}_table.#{value}"
							return_query = return_query.joins("LEFT JOIN #{association} as #{arg}_table ON #{self.table_name}.id = #{arg}_table.#{self.table_name.singularize}_id AND #{arg}_table.#{key} = '#{arg}'")
						else
							orders << "#{arg}"
						end
					end
			
				end
				return_query.order(orders.join(", "))
			end
			
			######################
			# external arguments #
			######################
			define_singleton_method :external_attributes do
				return args
			end
			
			before_save do
				args.each do |attribute|
					(found_item = self.send(association).detect{|amd| amd.send(key) == attribute.to_s} || self.send(association).build("#{key}": attribute)).send( "#{value}=", self.send(attribute) ) if self.send("#{attribute}_changed?")
					found_item.delete if found_item and found_item.send(value).nil?
				end
			end
			
			after_save do
				args.each do |attribute|
					self.instance_variable_set("@old_saved_#{attribute}",self.send(attribute))
				end
			end
			
			# define methods
			define_method("reload") do |options = nil|
				super options
				args.each do |attribute|
					self.remove_instance_variable("@#{attribute}") if self.instance_variable_defined?("@#{attribute}")
					self.remove_instance_variable("@old_saved_#{attribute}") if self.instance_variable_defined?("@old_saved_#{attribute}")
				end
				self
			end
			args.each do |attribute|
				define_method("#{attribute}_changed?") do
					self.send(attribute) != self.instance_variable_get("@old_saved_#{attribute}")
				end
				define_method("#{attribute}") do
					# have to set attribute and old_sved_attribute here because of the includes and for minimlize queries to db we can't make it after initialize
					self.instance_variable_set("@#{attribute}", self.send(association).detect{|amd| amd.send(key) == attribute.to_s}.try("value")) unless self.instance_variable_defined?("@#{attribute}")
					self.instance_variable_set("@old_saved_#{attribute}", self.send(association).detect{|amd| amd.send(key) == attribute.to_s}.try("value")) unless self.instance_variable_defined?("@old_saved_#{attribute}")
					self.instance_variable_get("@#{attribute}")
				end
				define_method("#{attribute}=") do |attr|
					self.instance_variable_set("@#{attribute}",attr)
				end
				define_method("#{attribute}_obj") do |attr|
					
				end
			end
			
		end
	end
end