# frozen_string_literal: true

module RTerm
  class Terminal
    class HostElement
      attr_accessor :class_name, :text_content
      attr_reader :attributes, :children, :dataset, :style, :tag_name

      def initialize(tag_name: "div", class_name: "rterm")
        @tag_name = tag_name
        @class_name = class_name
        @text_content = ""
        @attributes = {}
        @children = []
        @dataset = {}
        @style = {}
      end

      def append_child(child)
        @children << child unless @children.include?(child)
        child.parent = self if child.respond_to?(:parent=)
        child
      end

      def remove_child(child)
        @children.delete(child)
        child.parent = nil if child.respond_to?(:parent=)
        child
      end

      def set_attribute(name, value)
        @attributes[name.to_s] = value
      end

      def get_attribute(name)
        @attributes[name.to_s]
      end

      def remove_attribute(name)
        @attributes.delete(name.to_s)
      end

      def to_h
        {
          tag_name: @tag_name,
          class_name: @class_name,
          text_content: @text_content,
          attributes: @attributes.dup,
          dataset: @dataset.dup,
          style: @style.dup,
          children: @children.map { |child| child.respond_to?(:to_h) ? child.to_h : child }
        }
      end

      alias appendChild append_child
      alias removeChild remove_child
      alias className class_name
      alias className= class_name=
      alias textContent text_content
      alias textContent= text_content=
      alias setAttribute set_attribute
      alias getAttribute get_attribute
      alias removeAttribute remove_attribute
    end

    class TextAreaElement
      include Common::EventEmitter

      attr_accessor :parent, :selection_end, :selection_start, :value
      attr_reader :attributes, :dataset, :style

      def initialize(terminal, parent: nil, label: "Terminal input")
        @terminal = terminal
        @parent = parent
        @value = ""
        @composition = ""
        @focused = false
        @composing = false
        @selection_start = 0
        @selection_end = 0
        @attributes = {}
        @dataset = {}
        @style = {}
        set_attribute("aria-label", label)
        set_attribute("autocapitalize", "off")
        set_attribute("autocomplete", "off")
        set_attribute("spellcheck", "false")
      end

      def tag_name
        "textarea"
      end

      def focused?
        @focused
      end

      def composing?
        @composing
      end

      def composition
        @composition.dup
      end

      def focus
        @terminal.focus
      end

      def blur
        @terminal.blur
      end

      def input(data, was_user_input: true)
        text = data.to_s
        set_value(text)
        emit(:input, input_payload(text, was_user_input: was_user_input))
        @terminal.input(text, was_user_input)
      end

      def paste(data)
        text = data.to_s
        set_value(text)
        emit(:paste, input_payload(text, was_user_input: true))
        @terminal.paste(text)
      end

      def composition_start(data = nil)
        text = data.to_s
        set_composition(text, active: true)
        emit(:composition_start, composition_payload(:composition_start, text))
        @terminal.composition_start(text)
      end

      def composition_update(data)
        text = data.to_s
        set_composition(text, active: true)
        emit(:composition_update, composition_payload(:composition_update, text))
        @terminal.composition_update(text)
      end

      def composition_end(data = nil, commit: true)
        text = data.nil? ? @composition : data.to_s
        set_composition(text, active: false)
        emit(:composition_end, composition_payload(:composition_end, text, committed: commit))
        @terminal.composition_end(text, commit: commit)
      end

      def set_focused(value)
        @focused = !!value
        @dataset["focused"] = @focused.to_s
        self
      end

      def set_value(text)
        @value = text.to_s
        @selection_start = @value.length
        @selection_end = @value.length
        @value
      end

      def set_composition(text, active:)
        @composition = text.to_s
        @composing = !!active
        @dataset["composing"] = @composing.to_s
        @dataset["composition"] = @composition
        self
      end

      def clear
        set_value("")
      end

      def set_attribute(name, value)
        @attributes[name.to_s] = value
      end

      def get_attribute(name)
        @attributes[name.to_s]
      end

      def remove_attribute(name)
        @attributes.delete(name.to_s)
      end

      def to_h
        {
          tag_name: tag_name,
          value: @value,
          focused: @focused,
          composing: @composing,
          composition: @composition,
          selection_start: @selection_start,
          selection_end: @selection_end,
          attributes: @attributes.dup,
          dataset: @dataset.dup,
          style: @style.dup
        }
      end

      alias focused focused?
      alias composing composing?
      alias isFocused focused?
      alias isComposing composing?
      alias compositionStart composition_start
      alias compositionUpdate composition_update
      alias compositionEnd composition_end
      alias setAttribute set_attribute
      alias getAttribute get_attribute
      alias removeAttribute remove_attribute

      private

      def input_payload(text, was_user_input:)
        {
          data: text,
          value: @value,
          was_user_input: was_user_input
        }
      end

      def composition_payload(event, text, committed: false)
        {
          event: event,
          data: text,
          value: @value,
          composing: @composing,
          committed: committed
        }
      end
    end
  end
end
