require 'json'
require 'yaml'

# :nodoc:
module Prmd
  # Schema object
  class Schema
    # @return [Hash] data
    attr_reader :data

    # @param [Hash<String, Object>] new_data
    def initialize(new_data = {})
      @data = convert_type_to_array(new_data)
      @schemata_examples = {}
    end

    #
    # @param [Object] datum
    # @return [Object] same type as the input object
    def convert_type_to_array(datum)
      case datum
      when Array
        datum.map { |element| convert_type_to_array(element) }
      when Hash
        if datum.key?('type') && datum['type'].is_a?(String)
          datum['type'] = [*datum['type']]
        end
        datum.each_with_object({}) do |(k, v), hash|
          if k == 'example' # We don't want to convert 'type' keys within an example into arrays
            hash[k] = v
          else
            hash[k] = convert_type_to_array(v)
          end
        end
      else
        datum
      end
    end

    # @param [String] key
    # @return [Object]
    def [](key)
      @data[key]
    end

    # @param [String] key
    # @param [Object] value
    def []=(key, value)
      @data[key] = value
    end

    # Merge schema data with provided schema
    #
    # @param [Hash, Prmd::Schema] schema
    # @return [void]
    def merge!(schema)
      if schema.is_a?(Schema)
        @data.merge!(schema.data)
      else
        @data.merge!(schema)
      end
    end

    #
    # @param [Hash, String] reference
    def dereference(reference)
      if reference.is_a?(Hash)
        if reference.key?('$ref')
          value = reference.dup
          key = value.delete('$ref')
        else
          return [nil, reference] # no dereference needed
        end
      else
        key, value = reference, {}
      end
      begin
        datum = @data
        key.gsub(/[^#]*#\//, '').split('/').each do |fragment|
          datum = datum[fragment]
        end
        # last dereference will have nil key, so compact it out
        # [-2..-1] should be the final key reached before deref
        dereferenced_key, dereferenced_value = dereference(datum)
        [
          [key, dereferenced_key].compact.last,
          [dereferenced_value, value].inject({}, &:merge)
        ]
      rescue => error
        $stderr.puts("Failed to dereference `#{key}`")
        raise error
      end
    end

    # @param [Hash] value
    def schema_value_example(value)
      if value.has_key?('example')
        if value['example'].is_a?(Hash) && value['example'].has_key?('oneOf')
          value['example']['oneOf'][0]
        else
          value['example']
        end
      elsif value.key?('anyOf')
        id_ref = value['anyOf'].find do |ref|
          ref['$ref'] && ref['$ref'].split('/').last == 'id'
        end
        ref = id_ref || value['anyOf'].first
        schema_example(ref)
      elsif value.key?('oneOf')
        id_ref = value['oneOf'].find do |ref|
          ref['$ref'] && ref['$ref'].split('/').last == 'id'
        end
        ref = id_ref || value['oneOf'].first
        schema_example(ref)
      elsif value.key?('properties') # nested properties
        schema_example(value)
      elsif value.key?('items') # array of objects
        _, items = dereference(value['items'])
        if value['items'].key?('example')
          if items["example"].is_a?(Array)
            items["example"]
          else
            [items['example']]
          end
        elsif items.key?('oneOf')
          id_ref = items['oneOf'].find do |ref|
            ref['$ref'] && ref['$ref'].split('/').last == 'id'
          end
          ref = id_ref || items['oneOf'].first
          [schema_example(ref)]
        else
          [schema_example(items)]
        end
      end
    end

    def recursive_dref(ref)
      _, deref = dereference(ref)
      if deref.is_a?(Hash)
        deref.each do |key, value|
        end
      end
    end

    # @param [Hash, String] schema
    def schema_example(schema)
      _, dff_schema = dereference(schema)
      if dff_schema.has_key?('example')

        if dff_schema['example'].is_a?(String)
          dff_schema['example']
        else
          key, ref = recursive_deref(dff_schema['example'])
          schema_example(ref)
        end
      elsif dff_schema.has_key?('allOf')
        example = {}
        dff_schema['allOf'].each do |object|
          temp_example = {}
          if object.has_key?("$ref")
            _, deref = dereference(object['$ref'])
            temp_example = schema_example(deref)
          else            
            temp_example = schema_example(object)
          end
          temp_example.each do |key, value|
            example[key] = value
          end
        end
        example
      elsif dff_schema.has_key?('properties')
        example = {}
        dff_schema['properties'].each do |key, value|
          _, value = dereference(value)
          example[key] = schema_value_example(value)
        end
        example
      elsif dff_schema.key?('items')
        schema_value_example(dff_schema)
      end
    end

    # @param [String] schemata_id
    def schemata_example(schemata_id)
      _, schema = dereference("#/definitions/#{schemata_id}")
      @schemata_examples[schemata_id] ||= begin
        schema_example(schema)
      end
    end

    # Retrieve this schema's href
    #
    # @return [String, nil]
    def href
      (@data['links'] && @data['links'].find { |link| link['rel'] == 'self' } || {})['href']
    end

    # Convert Schema to JSON
    #
    # @return [String]
    def to_json
      new_json = JSON.pretty_generate(@data)
      # nuke empty lines
      new_json = new_json.split("\n").reject(&:empty?).join("\n") + "\n"
      new_json
    end

    # Convert Schema to YAML
    #
    # @return [String]
    def to_yaml
      YAML.dump(@data)
    end

    # Convert Schema to String
    #
    # @return [String]
    def to_s
      to_json
    end

    private :convert_type_to_array
    protected :data
  end
end
