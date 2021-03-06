(require 'polymode-common)

;;; ROOT CLASS
(defclass polymode (eieio-instance-inheritor) ()
  "Root polymode class.")


;;; CONFIG
(defclass pm-config (polymode) 
  ((basemode
    :initarg :basemode
    :initform 'pm-base/blank
    :type symbol
    :custom symbol
    :documentation
    "Symbol pointing to an object of class pm-submode
    representing the base submode.")
   (minor-mode
    :initarg :minor-mode
    :initform 'polymode-minor-mode
    :type symbol
    :custom symbol
    :documentation
    "Symbol pointing to minor-mode function that should be
    activated in all buffers (base and indirect). This is a
    \"glue\" mode and is `polymode-minor-mode' by default.")
   (lighter
    :initarg :lighter
    :initform " PM"
    :type string
    :custom string
    :documentation "Modline lighter.")
   (exporters
    :initarg :exporters
    :initform '(pm-exporter/pandoc)
    :type list
    :custom list
    :documentation
    "List of names of polymode exporters available for this polymode.")
   (exporter
    :initarg :exporter
    :initform nil
    :type (or null symbol)
    :custom symbol
    :documentation
    "Current exporter name. If non-nil should be the name of the
    default exporter for this polymode. Can be set with
    `polymode-set-exporter' command.")
   (weavers
    :initarg :weavers
    :initform '()
    :type list
    :custom list
    :documentation
    "List of names of polymode weavers available for this polymode.")
   (weaver
    :initarg :weaver
    :initform nil
    :type (or null symbol)
    :custom symbol
    :documentation
    "Current weaver name. If non-nil this is the default weaver
    for this polymode. Can be dynamically set with
    `polymode-set-weaver'")
   (map
    :initarg :map
    :initform 'polymode-mode-map
    :type (or symbol list)
    "Has a similar role as the :keymap argument in
     `define-polymode' with the difference that this argument is
     inherited through cloning but :keymap argument is not. That
     is, child objects derived through clone will inherit
     the :map argument of its parents as follows. If :map is nil
     or an alist of keys, the parent is inspected for :map
     argument and the keys are merged. If :map is a symbol, it
     should be a keymap, in which case this keymap is used and no
     parents are further inspected for :map slot. If :map is an
     alist it should be suitable to be passed to
     `easy-mmode-define-keymap'.")
   (init-functions
    :initarg :init-functions
    :initform '()
    :type list
    :documentation
    "List of functions to run at the initialization time.
     All init-functions in the inheritance chain are called. Parents
     hooks first. So, if current config object C inherits from object
     B, which in turn inherits from object A. Then A's init-functions
     are called first, then B's and then C's.

     Either customize this slot or use `object-add-to-list' function.")
   (-basemode
    :type (or null pm-submode)
    :documentation
    "Instantiated submode object of class `pm-submode'. Dynamically populated.")
   (-chunkmodes
    :type list
    :initform '()
    :documentation
    "List of submodes objects that inherit from `pm-chunkmode'. Dynamically populated.")
   (-buffers
    :initform '()
    :type list
    :documentation
    "Holds all buffers associated with current buffer. Dynamically populated.")
   (-hist
    :initform '()
    :type list
    :documentation "Internal. Used to store various user history
    values. Use `pm--get-hist' and `pm--put-hist' to place key
    value pairs into this list."))
  
  "Configuration for a polymode. Each polymode buffer contains a local
variable `pm/config' instantiated from this class or a subclass
of this class.")


(defclass pm-config-one (pm-config)
  ((chunkmode
    :initarg :chunkmode
    :type symbol
    :custom symbol
    :documentation
    "Symbol of the submode. At run time this object is cloned
     and placed in -chunkmodes slot."))
  
  "Configuration for a simple polymode that allows only one
submode. For example noweb.")


(defclass pm-config-multi (pm-config)
  ((chunkmodes
    :initarg :chunkmodes
    :type list
    :custom list
    :initform nil
    :documentation
    "List of names of the submode objects that are associated
     with this configuration. At initialization time, all of
     these are cloned and plased in -chunkmodes slot."))
  
  "Configuration for a polymode that allows multiple known in
advance submodes.")


(defclass pm-config-multi-auto (pm-config-multi)
  ((auto-chunkmode
    :initarg :auto-chunkmode
    :type symbol
    :custom symbol
    :documentation
    "Name of pm-chunkmode-auto object (a symbol). At run time
     this object is cloned and placed in -auto-chunkmodes with
     coresponding :mode slot initialized at run time.")
   (-auto-chunkmodes
    :type list
    :initform '()
    :documentation
    "List of chunkmode objects that are auto-generated in
    pm/get-span method for this class."))
  
  "Configuration for a polymode that allows multiple submodes
that are not known in advance. Examples are org-mode and markdown.")



;;; SUBMODE CLASSES
(defclass pm-submode (polymode)
  ((mode
    :initarg :mode
    :type symbol
    :initform nil
    :custom symbol)
   (protect-indent-line
    :initarg :protect-indent-line
    :type boolean
    :initform t
    :custom boolean
    :documentation
    "Whether to modify local `indent-line-function' by narrowing
    to current span first")
   (indent-offset
    :initarg :indent-offset
    :type integer
    :initform 0
    :documentation
    "Offset to add when indenting chunk's line. Takes efeect only
    when :protect-indent-line is non-nil.")
   (font-lock-narrow
    :initarg :font-lock-narrow
    :type boolean
    :initform t
    :documentation
    "Whether to narrow to span during font lock")
   (adjust-face
    :initarg :adjust-face
    :type (or number face list)
    :custom (or number face list)
    :initform nil
    :documentation
    "Fontification adjustments chunk face. It should be either,
    nil, number, face or a list of text properties as in
    `put-text-property' specification.

    If nil no highlighting occurs. If a face, use that face. If a
    number, it is a percentage by which to lighten/darken the
    default chunk background. If positive - lighten the
    background on dark themes and darken on light thems. If
    negative - darken in dark thems and lighten in light
    thems.")
   (-buffer
    :type (or null buffer)
    :initform nil))
  
  "Representatioin of the submode object.")

(defclass pm-basemode (pm-submode)
  ()
  "Representation of the basemode objects. Basemodes are the
  main (parent) modes in the buffer. For example for a the
  web-mdoe the basemode is `html-mode', for nowweb mode the base
  mode is usually `latex-mode', etc.")

(defclass pm-chunkmode (pm-submode)
  ((adjust-face
    :initform 2)
   (head-mode
    :initarg :head-mode
    :type symbol
    :initform 'fundamental-mode
    :custom symbol
    :documentation
    "Chunks' header mode. If set to 'body, the head is considered
    part of the chunk body. If set to 'base, head is considered
    part of the including base mode.")
   (-head-buffer
    :type (or null buffer)
    :initform nil
    :documentation
    "This buffer is set automatically to -buffer if :head-mode is
    'body, and to base-buffer if :head-mode is 'base")
   (tail-mode
    :initarg :tail-mode
    :type symbol
    :initform nil
    :custom symbol
    :documentation
    "If nil, it is the same as :HEAD-MODE. Otherwise, the same
    rules as for the :head-mode apply.")
   (-tail-buffer
    :initform nil
    :type (or null buffer))
   (head-reg
    :initarg :head-reg
    :initform ""
    :type (or string symbol)
    :custom (or string symbol)
    :documentation "Regexp for the chunk start (aka head)")
   (tail-reg
    :initarg :tail-reg
    :initform ""
    :type (or string symbol)
    :custom (or string symbol)
    :documentation "Regexp for chunk end (aka tail)")
   (head-adjust-face
    :initarg :head-adjust-face
    :initform font-lock-type-face
    :type (or null number face list)
    :custom (or null number face list)
    :documentation
    "Can be a number, list or face.")
   (tail-adjust-face
    :initarg :tail-adjust-face
    :initform nil
    :type (or null number face list)
    :custom (or null number face list)
    :documentation
    "Can be a number, list or face. If nil, take the
configuration from :head-adjust-face."))
  
  "Representation of an inner (aka chunk) submode in a buffer.")

(defclass pm-chunkmode-auto (pm-chunkmode)
  ((retriever-regexp
    :initarg :retriever-regexp
    :type (or null string)
    :custom string
    :initform nil
    :documentation
    "Regexp that is used to retrive the modes symbol from the
    head of the submode chunk. fixme: elaborate")
   (retriever-num
    :initarg :retriever-num
    :type integer
    :custom integer
    :initform 1
    :documentation
    "Subexpression to be matched by :retriver-regexp")
   (retriever-function
    :initarg :retriever-function
    :type symbol
    :custom symbol
    :initform nil
    :documentation
    "Function name that is used to retrive the modes symbol from
    the head of the submode chunk. fixme: elaborate"))

  "Representation of an inner submode")

(provide 'polymode-classes)
