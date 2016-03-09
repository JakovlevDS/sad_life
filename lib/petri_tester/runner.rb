module PetriTester
  class Runner
    attr_reader :tokens, :execution_callbacks, :production_callbacks

    # @param net [Petri::Net]
    def initialize(net)
      @net = net
      @tokens = []

      @execution_callbacks = {}
      @production_callbacks = {}

      @initialized = false
    end

    # Binds callback on a net transition
    # @param transition_identifier [String]
    # @param block [Proc]
    def on(transition_identifier, &block)
      raise ArgumentError, 'No block given' unless block
      @execution_callbacks[transition_by_identifier!(transition_identifier)] = block
    end

    # Binds producing callback on a net transition
    # @param transition_identifier [String]
    # @param block [Proc]
    def produce(transition_identifier, &block)
      raise ArgumentError, 'No block given' unless block
      @production_callbacks[transition_by_identifier!(transition_identifier)] = block
    end

    # @param transition_identifier [String]
    def execute!(transition_identifier, params = {})
      init
      target_transition = transition_by_identifier!(transition_identifier)

      PetriTester::ExecutionChain.new(target_transition).each do |level|
        level.each do |transition|
          if transition == target_transition
            perform_action!(transition, params)
          else
            perform_action(transition, params)
          end
        end
      end

      execute_automated!(source: target_transition)
    end

    # @param transition [Petri::Transition]
    # @return [true, false]
    def transition_enabled?(transition)
      transition.input_places.all? do |place|
        @tokens.any? { |token| token.place == place }
      end
    end

    # @param place [Place]
    # @param source [Transition, nil]
    # @return [Token]
    def put_token(place, source: nil)
      Petri::Token.new(place, source).tap do |token|
        @tokens << token

        if place.finish?
          links = @net.places.select { |p| p.start? && p.identifier == place.identifier }

          links.each do |place|
            @tokens << Petri::Token.new(place)
          end
        end
      end
    end

    # @param place [Place]
    # @return [Token, nil]
    def remove_token(place)
      @tokens.each do |token|
        if token.place == place
          @tokens.delete(token)
          return token
        end
      end
      nil
    end

    # @param token [Token]
    def restore_token(token)
      @tokens << token
    end

    # @param place [Place]
    # @return [Array<Token>]
    def reset_tokens(place)
      [].tap do |result|
        @tokens.each do |token|
          result << token if token.place == place
        end

        result.each { |token| @tokens.delete(token) }
      end
    end

    # Puts tokens in start places
    # Executes automated actions if any enabled
    # Fills out weights for futher usage
    def init
      return if @initialized

      # Fill start places with tokens to let the process start
      start_places.each(&method(:put_token))

      # Without weights assigned transition execution path search won't work
      PetriTester::DistanceWeightIndexator.new(@net).reindex

      execute_automated!

      @initialized = true
    end

    private

    # Runs all automated transitions which are enabled at the moment
    # @param source [Petri::Transition]
    def execute_automated!(source: nil)
      @net.transitions.each do |transition|
        if transition_enabled?(transition) && transition.automated? && source != transition
          perform_action!(transition)
        end
      end
    end

    # Fires transition if enabled, executes binded block
    # @param transition [Petri::Transition]
    # @param params [Hash]
    def perform_action(transition, *args)
      if transition_enabled?(transition)
        perform_action!(transition)
      end
    end

    # Fires transition, executes binded block
    # @raise
    # @param transition [Petri::Transition]
    # @param params [Hash]
    def perform_action!(transition, params = {})
      Action.new(self, transition, params).perform!
    end

    # @param identifier [String]
    # @raise [ArgumentError] if transition is not found
    # @return [Transition]
    def transition_by_identifier!(identifier)
      @net.node_by_identifier(identifier) or raise ArgumentError, "No such transition '#{identifier}'"
    end

    # @param identifier [String]
    # @return [Array<Petri::Place>]
    def places_by_identifier(identifier)
      identifier = identifier.to_s
      @net.places.select { |node| node.identifier == identifier }
    end

    # @return [Array<Petri::Place>]
    def start_places
      @net.places.select do |place|
        if place.start?
          connected = places_by_identifier(place.identifier)
          connected.one? || connected.empty?
        end
      end
    end
  end
end
