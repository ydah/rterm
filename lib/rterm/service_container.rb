# frozen_string_literal: true

module RTerm
  # Minimal service locator used by the headless/core layers.
  class ServiceContainer
    class ServiceNotFound < KeyError; end

    # @return [void]
    def initialize
      @registrations = {}
      @instances = {}
    end

    # @param service_id [Symbol]
    # @param instance_or_factory [Object, #call]
    # @return [Object]
    def register(service_id, instance_or_factory)
      @registrations[service_id] = instance_or_factory
      @instances.delete(service_id)
      instance_or_factory
    end

    # @param service_id [Symbol]
    # @return [Object]
    def get(service_id)
      raise ServiceNotFound, "Service not registered: #{service_id}" unless has?(service_id)

      return @instances[service_id] if @instances.key?(service_id)

      registration = @registrations[service_id]
      @instances[service_id] = registration.respond_to?(:call) ? registration.call : registration
    end

    # @param service_id [Symbol]
    # @return [Boolean]
    def has?(service_id)
      @registrations.key?(service_id)
    end

    # @param service_id [Symbol]
    # @return [Boolean]
    def has_service?(service_id)
      has?(service_id)
    end
  end

  module Services
    BUFFER_SERVICE = :buffer_service
    OPTIONS_SERVICE = :options_service
    LOG_SERVICE = :log_service
    UNICODE_SERVICE = :unicode_service
    CHARSET_SERVICE = :charset_service
    CORE_SERVICE = :core_service
    DECORATION_SERVICE = :decoration_service
    OSC_LINK_SERVICE = :osc_link_service
  end
end
