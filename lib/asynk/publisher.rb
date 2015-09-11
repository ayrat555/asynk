module Asynk
  class Publisher
    class << self
      def publish(routing_key, params = {})
        Asynk.broker.pubisher_channel_pool.with do |channel|
          exchange = channel.topic(Asynk.config[:mq_exchange])
          Asynk.logger.info "Sending asynk message to #{routing_key} with params: #{params}"
          exchange.publish(params.to_json, routing_key: routing_key)
        end
      end

      def sync_publish(routing_key, params = {})
        start_time = Time.now.to_f
        wait_timeout = params.delete(:timeout) || Asynk.config[:sync_publish_wait_timeout]
        load_cellulooid
        response = nil
        Asynk.broker.pubisher_channel_pool.with do |channel|
          exchange = channel.topic(Asynk.config[:mq_exchange])

          reply_queue = channel.queue('', exclusive: true)
          condition = Celluloid::Condition.new
          call_id = SecureRandom.uuid

          reply_queue.subscribe do |delivery_info, properties, payload|
            condition.signal(payload) if properties[:correlation_id] == call_id
          end

          Asynk.logger.info "Sending synk message to #{routing_key} with params: #{params}"
          exchange.publish(params.to_json, routing_key: routing_key, correlation_id: call_id, reply_to: reply_queue.name)
          Asynk.logger.debug "Request round trip time: #{((Time.now.to_f - start_time)*1000).round(2)} ms"
          response = condition.wait(wait_timeout)
        end
        Asynk::Response.try_to_create_from_hash(response)
      end

      def load_cellulooid
        require 'celluloid'
        require 'celluloid/io'
      end
    end
  end
end