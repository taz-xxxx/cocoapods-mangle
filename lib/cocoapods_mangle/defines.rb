module CocoapodsMangle
  # Generates mangling defines from a provided list of binaries
  module Defines
    # @param  [String] prefix
    #         The prefix to prefix to mangled symbols
    # @param  [Array<String>] binaries_to_mangle
    #         The binaries containing symbols to be mangled
    # @return [Array<String>] The mangling defines
    def self.mangling_defines(prefix, binaries_to_mangle)
      classes = classes(binaries_to_mangle)
      constants = constants(binaries_to_mangle)
      category_selectors = category_selectors(binaries_to_mangle, classes)

      defines = prefix_symbols(prefix, classes)
      defines += prefix_symbols(prefix, constants)
      defines += prefix_selectors(prefix, category_selectors)
      defines
    end

    # Get the classes defined in a list of binaries
    # @param  [Array<String>] binaries
    #         The binaries containing symbols to be mangled
    # @return [Array<String>] The classes defined in the binaries
    def self.classes(binaries)
      all_symbols = run_nm(binaries, '-gU')
      class_symbols = all_symbols.select do |symbol|
        symbol[/OBJC_CLASS_\$_/]
      end
      class_symbols = class_symbols.map { |klass| klass.gsub(/^.*\$_/, '') }
      class_symbols.uniq
    end

    # Get the constants defined in a list of binaries
    # @param  [Array<String>] binaries
    #         The binaries containing symbols to be mangled
    # @return [Array<String>] The constants defined in the binaries
    def self.constants(binaries)
      all_symbols = run_nm(binaries, '-gU')
      consts = all_symbols.select { |const| const[/ S /] }
      consts = consts.reject { |const| const[/_OBJC_/] }
      consts = consts.map! { |const| const.gsub(/^.* _/, '') }
      consts = consts.uniq

      other_consts = all_symbols.select { |const| const[/ T /] }
      other_consts = other_consts.map! { |const| const.gsub(/^.* _/, '') }
      other_consts = other_consts.uniq

      consts + other_consts
    end

    # Get the category selectors defined in a list of binaries
    # @note   Selectors on classes which are being mangled will not be mangled
    # @param  [Array<String>] binaries
    #         The binaries containing symbols to be mangled
    # @param  [Array<String>] classes
    #         The classes which are being mangled
    # @return [Array<String>] The category selectors defined in the binaries
    def self.category_selectors(binaries, classes)
      symbols = run_nm(binaries, '-U')
      selectors = symbols.select { |selector| selector[/ t [-|+]\[[^ ]*\([^ ]*\) [^ ]*\]/] }
      selectors = selectors.reject do |selector|
        class_name = selector[/[-|+]\[(.*?)\(/m, 1]
        classes.include? class_name
      end
      selectors = selectors.map { |selector| selector[/[^ ]*\]\z/][0...-1] }
      selectors = selectors.map { |selector| selector.split(':').first }
      selectors.uniq
    end

    # Prefix a given list of symbols
    # @param  [String] prefix
    #         The prefix to prepend
    # @param  [Array<String>] symbols
    #         The symbols to prefix
    def self.prefix_symbols(prefix, symbols)
      symbols.map do |symbol|
        "#{symbol}=#{prefix}#{symbol}"
      end
    end

    # Prefix a given list of selectors
    # @param  [String] prefix
    #         The prefix to use
    # @param  [Array<String>] selectors
    #         The selectors to prefix
    def self.prefix_selectors(prefix, selectors)
      selectors_to_prefix = selectors
      defines = []

      property_setters = selectors.select { |selector| selector[/\Aset[A-Z]/] }
      property_setters.each do |property_setter|
        property_getter = selectors.find do |selector|
          upper_getter = property_setter[3..-1]
          lower_getter = upper_getter[0, 1].downcase + upper_getter[1..-1]
          selector == upper_getter || selector == lower_getter
        end
        next if property_getter.nil?

        selectors_to_prefix.reject! { |selector| selector == property_setter }
        selectors_to_prefix.reject! { |selector| selector == property_getter }

        defines << "#{property_setter}=set#{prefix}#{property_getter}"
        defines << "#{property_getter}=#{prefix}#{property_getter}"
      end

      defines += prefix_symbols(prefix, selectors_to_prefix)
      defines
    end

    def self.run_nm(binaries, flags)
      `nm #{flags} #{binaries.join(' ')}`.split("\n")
    end
  end
end
