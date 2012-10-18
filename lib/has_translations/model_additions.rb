module HasTranslations
  module ModelAdditions
    extend ActiveSupport::Concern

    module ClassMethods

      def translation_table
        self.has_translations_options[:translation_class].table_name
      end

      def prefixed_language_id
        "#{self.translation_table}.language_id"
      end

      def translated(language_id)
        where(["#{prefixed_language_id} = ?", language_id]).joins(:translations).readonly(false)
      end

      def where_language_id(language_id)
        translated(language_id)
      end

      def has_translations(*attrs)
        new_options = attrs.extract_options!
        options = {
          :fallback => false,
          :reader => true,
          :writer => false,
          :nil => '',
          :autosave => new_options[:writer],
          :translation_class => nil
        }.merge(new_options)

        translation_class_name =  options[:translation_class].try(:name) || "#{self.model_name}Translation"
        options[:translation_class] ||= translation_class_name.constantize

        options.assert_valid_keys([:fallback, :reader, :writer, :nil, :autosave, :translation_class])

        belongs_to = self.model_name.demodulize.underscore.to_sym

        class_attribute :has_translations_options
        self.has_translations_options = options

        # associations, validations and scope definitions
        has_many :translations, :class_name => translation_class_name, :dependent => :destroy, :autosave => options[:autosave]
        options[:translation_class].belongs_to belongs_to
        options[:translation_class].validates_presence_of :language_id
        options[:translation_class].validates_uniqueness_of :language_id, :scope => :"#{belongs_to}_id"

        # Optionals delegated readers
        if options[:reader]
          attrs.each do |name|
            send :define_method, name do |*args|
              language_id = args.first || get_language_id_from_i18n
              translation = self.translation(language_id)
              translation.try(name) || has_translations_options[:nil]
            end
          end
        end

        # Optionals delegated writers
        if options[:writer]
          attrs.each do |name|
            send :define_method, "#{name}_before_type_cast" do
              translation = self.translation(get_language_id_from_i18n, false)
              translation.try(name)
            end

            send :define_method, "#{name}=" do |value|
              translation = find_or_build_translation(get_language_id_from_i18n)
              translation.send(:"#{name}=", value)
            end
          end
        end

      end
    end

    def find_or_create_translation(language_id)
      (find_translation(language_id) || self.has_translations_options[:translation_class].new).tap do |t|
        t.language_id = language_id
        t.send(:"#{self.class.model_name.demodulize.underscore.to_sym}_id=", self.id)
      end
    end

    def find_or_build_translation(language_id)
      (find_translation(language_id) || self.translations.build).tap do |t|
        t.language_id = language_id
      end
    end

    def translation(language_id, fallback=has_translations_options[:fallback])
      find_translation(language_id) || (fallback && !translations.blank? ? translations.detect { |t| t.language_id == 1 } || translations.first : nil)
    end

    def all_translations
      t = LANGUAGE_HASH.map do |l_str, l_id|
        [l_id, find_or_create_translation(l_id)]
      end
      ActiveSupport::OrderedHash[t]
    end

    def form_translations
      translations.length > 0 ? translations : all_translations.values
    end

    def has_translation?(language_id)
      find_translation(language_id).present?
    end

    def find_translation(language_id)
      translations.detect { |t| t.language_id == language_id } || translations[0]
    end


    def get_language_id_from_i18n
      LANGUAGE_HASH[I18n.locale.to_s.split("-")[0].to_sym] || LANGUAGE_HASH[:en]
    end
  end
end
