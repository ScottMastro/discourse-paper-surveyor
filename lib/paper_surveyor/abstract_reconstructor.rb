# frozen_string_literal: true

module PaperSurveyor
  # OpenAlex returns abstracts as an inverted index:
  #   { "Hello": [0], "world": [1, 5], ... }
  # i.e. word => list of token positions. Reconstruct the plain text.
  module AbstractReconstructor
    module_function

    def call(inverted_index)
      return nil if inverted_index.blank?

      length = inverted_index.values.flatten.max.to_i + 1
      tokens = Array.new(length)
      inverted_index.each do |word, positions|
        positions.each { |pos| tokens[pos] = word }
      end
      TextCleaner.to_plain(tokens.compact.join(" "))
    end
  end
end
