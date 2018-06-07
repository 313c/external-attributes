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
	
	def external_attributes_for ( association_name, key, value, *args )
		if args.last.is_a? Hash
			last_hash = args.pop
			args += last_hash.keys
		end
		
		@external_attributes_args ||= []
		@external_attributes_args += args
		@external_attributes_args = @external_attributes_args.uniq
		#raise ArgumentError unless @external_attributes_args.detect{ |e| @external_attributes_args.count(e) > 1 }.blank?
		
		
		class_eval do
			attr_accessor :changed_external_attributes unless method_defined? :changed_external_attributes
			# @changed_external_attributes
			define_method("initialize") do |*options|
				super *options
				if !options.empty? and !(options.last.try(:keys) - (options.last.try(:keys) - self.class.external_attributes)).empty?
					self.class.external_attributes.each do |attribute|
						self.instance_variable_set("@#{attribute}", options.last[attribute]) if options.last[attribute]
					end
				end
			end unless method_defined? :initialize
			
			##################
			# external_where #
			##################
			define_singleton_method :external_where do |*where_args|
				where_args = where_args.last
				mds = Array.new
				class_name = self.reflect_on_association(association_name).klass.name
				foreign_key = self.reflect_on_association(association_name).foreign_key
				association_table_name = class_name.safe_constantize.table_name
				if where_args.first.is_a?(String)
					mds << class_name.safe_constantize.where(where_args).select(foreign_key).map{|md| md.send(foreign_key.to_sym)}
				else
					where_args.each do |k,v|
            # for value as range except date range
						if v.is_a?(Range) && !(v.first.respond_to?(:to_date) && v.first.to_date.present?)
              mds << class_name.safe_constantize.where("name=:name AND CAST(`#{value}` AS UNSIGNED) BETWEEN :min AND :max", name: k, min: v.first, max: v.last ).select(foreign_key).map{|md| md.send(foreign_key.to_sym)}
						elsif v.nil?
							mds << self.name.safe_constantize.select(:id).joins("LEFT JOIN #{association_table_name} as #{association_table_name}_#{k} ON #{association_table_name}_#{k}.#{foreign_key} = #{self.table_name}.id AND #{association_table_name}_#{k}.#{key} = '#{k}'").where("#{association_table_name}_#{k}.#{key} IS NULL").ids
            else
						  mds << class_name.safe_constantize.where(key => k, value => v).select(foreign_key).map{|md| md.send(foreign_key.to_sym)}
            end
					end
				end
				ids = mds.shift
				mds.each do |arr|
					ids = ids & arr
				end				
				return self.where(id: ids.uniq) unless ids.empty?
				self.where("1=0")
			end unless method_defined? :external_where
			
			##################
			# external_order #
			##################
			# remove_method :external_order if method_defined? :external_order
			define_singleton_method :external_order do |*order_args|
				orders = Array.new
				return_query = self
				order_args.each do |arg|
					if arg.is_a? Hash
						arg.each do |k, v|
							if k.to_sym.in?(@external_attributes_args)
								if v.is_a? Hash
									case v[:type]
									when :integer
										order = "cast(#{k}_table.#{value} as unsigned)"
									else
										order = "#{k}_table.#{value}"
									end
									order += " #{v[:dir]}" if v[:dir]
									orders << order
								else
									orders << "#{k}_table.#{value} #{v}"
								end
								# Rails.logger.info orders
								association_table_name = self.reflect_on_association(association_name).klass.name.safe_constantize.table_name
								foreign_key = self.reflect_on_association(association_name).foreign_key
								return_query = return_query.joins("LEFT JOIN #{association_table_name} as #{k}_table ON #{self.table_name}.id = #{k}_table.#{foreign_key} AND #{k}_table.#{key} = '#{k}'")
							else
								orders << "#{self.table_name}.#{k} #{v}"
							end
						end
					else
						if arg.to_sym.in?(@external_attributes_args)
							orders << "#{arg}_table.#{value}"
							return_query = return_query.joins("LEFT JOIN #{association_name} as #{arg}_table ON #{self.table_name}.id = #{arg}_table.#{self.table_name.singularize}_id AND #{arg}_table.#{key} = '#{arg}'")
						else
							orders << "#{arg}"
						end
					end
				end
				return_query.order(orders.join(", "))
			end unless method_defined? :external_order
			
			######################
			# external arguments #
			######################
			define_singleton_method :external_attributes do
				return @external_attributes_args
			end unless method_defined? :external_attributes
			
			after_initialize do
				self.changed_external_attributes ||= []
			end
			around_save do |activity, block|
				args.each do |attribute|
					should_serialize = true if last_hash.try(:keys).try(:include?, attribute) and last_hash[attribute][:serialize]
					(found_item = self.send(association_name).detect{|amd| amd.send(key) == attribute.to_s} || self.send(association_name).build("#{key}": attribute)).send( "#{value}=", (should_serialize ? self.send(attribute).to_yaml : self.send(attribute) ) ) if self.send("#{attribute}_changed?")
					self.changed_external_attributes << attribute.to_s if self.send("#{attribute}_changed?")
					found_item.delete if found_item and found_item.send(value).nil?
				end
				block.call
			end
			
			# define methods
			define_method("reload") do |options = nil|
				super options
				self.class.external_attributes.each do |attribute|
					self.remove_instance_variable("@#{attribute}") if self.instance_variable_defined?("@#{attribute}")
				end
				self
			end unless method_defined? :reload
			
			args.each do |attribute|
				define_method("#{attribute}_changed?") do
					changed_attributes.keys.map{|key| key.to_sym}.include?(attribute.to_sym)
				end
				define_method("#{attribute}_was") do
					changed_attributes.try(:[],attribute)
				end
				define_method("#{attribute}") do
					should_serialize = true if last_hash.try(:keys).try(:include?, attribute) and last_hash[attribute][:serialize]
					# have to set attribute and old_sved_attribute here because of the includes and for minimlize queries to db we can't make it after initialize
					unless self.instance_variable_defined?("@#{attribute}")
						from_db = self.send(association_name).detect{|amd| amd.send(key) == attribute.to_s}.try("value")
						if should_serialize and from_db.present?
							self.instance_variable_set("@#{attribute}", YAML.load(from_db))
						else
							self.instance_variable_set("@#{attribute}", from_db)
						end
					end
					self.instance_variable_get("@#{attribute}")
				end
				define_method("#{attribute}=") do |attr|
					@changed_attributes = changed_attributes.merge(ActiveSupport::HashWithIndifferentAccess.new({attribute => self.send(attribute)})) unless attr.blank? and self.send(attribute).blank? or attr == self.send(attribute)
					self.instance_variable_set("@#{attribute}",attr)
				end
			end
			
		end
	end
end
