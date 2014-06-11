module Milter
  class Client
    class EnvelopeAddress
      attr_reader :envelope_address
      attr_accessor :address_spec

      def initialize(envelope_address)
        @envelope_address = envelope_address
      end

      def extract_address
        return nil unless @envelope_address
        if Object.const_defined?(:Encoding)
          address = @envelope_address.dup.force_encoding("BINARY")
        else
          address = @envelope_address.dup
        end
        address = address[/<([^<>]*)>/, 1] ||
          address[/[^\s<>]+@[^\s<>]+/] || address[/[^\s<>]+/] || address
        address
      end

      def address_spec
        return @address_spec unless @address_spec.nil?
        address = extract_address
        if address.nil?
          @address_spec = nil
        else
          @address_spec = address.downcase
        end
      end

      def domain
        address = address_spec
        return nil unless address
        address.slice(/\A(.+)@(.+)\z/, 2)
      end
    end
  end
end
