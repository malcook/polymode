;; COMMON INITIALIZATION, UTILITIES and INTERNALS which didn't fit anywhere else

(eval-when-compile
  (require 'cl))
(require 'font-lock)
(require 'color)
(require 'eieio)
(require 'eieio-base)
(require 'eieio-custom)

;; esential vars
(defvar-local pm/config nil)
(defvar-local pm/submode nil)
(defvar-local pm/type nil)
(defvar-local polymode-major-mode nil)
(defvar-local pm--fontify-region-original nil)
(defvar-local pm--indent-line-function-original nil)
(defvar-local pm--syntax-begin-function-original nil)
;; (defvar-local pm--killed-once nil)
(defvar-local polymode-mode nil
  "This variable is t if current \"mode\" is a polymode.")

;; silence the compiler for now
(defvar pm--output-file nil)
(defvar pm--input-buffer nil)
(defvar pm--input-file nil)
(defvar pm/type)
(defvar pm/config)
(defvar pm/submode)
(defvar *span*)

;; core api from polymode.el, which relies on polymode-methods.el.
;; fixme: some of these are not api, rename
(declare-function pm/base-buffer "polymode")
(declare-function pm/get-innermost-span "polymode")
(declare-function pm/map-over-spans "polymode")
(declare-function pm/narrow-to-span "polymode")
(declare-function pm/fontify-region "polymode")
(declare-function pm/syntax-begin-function "polymode")

;; methods api from polymode-methods.el
(declare-function pm/initialize "polymode-methods")
(declare-function pm/get-buffer "polymode-methods")
(declare-function pm/select-buffer "polymode-methods")
(declare-function pm/install-buffer "polymode-methods")
(declare-function pm/get-adjust-face "polymode-methods")
(declare-function pm/get-span "polymode-methods")
(declare-function pm/indent-line "polymode-methods")

;; buffer manipulation function in polymode-methods.el
;; polymode-common.el:315:1:Warning: the following functions are not known to be defined:
;; pm--create-indirect-buffer, pm--setup-buffer, pm--span-at-point, polymode-select-buffer

;; temporary debugging facilities
(defvar pm--dbg-mode-line t)
(defvar pm--dbg-fontlock t)
(defvar pm--dbg-hook t)

;; other locals
(defvar-local pm--process-buffer nil)


;;; UTILITIES
(defun pm--display-file (ofile)
  (display-buffer (find-file-noselect ofile 'nowarn)))

(defun pm--get-available-mode (mode)
  "Check if MODE symbol is defined and is a valid function.
If so, return it, otherwise return 'fundamental-mode with a
warnign."
  (if (fboundp mode)
      mode
    (message "Cannot find %s function, using 'fundamental-mode instead" mode)
    'fundamental-mode))

(defun pm--get-indirect-buffer-of-mode (mode)
  (loop for bf in (oref pm/config -buffers)
        when (and (buffer-live-p bf)
                  (eq mode (buffer-local-value 'polymode-major-mode bf)))
        return bf))

;; ;; This doesn't work in 24.2, pcase bug ((void-variable xcar))
;; ;; Other pcases in this file don't throw this error
;; (defun pm--set-submode-buffer (obj type buff)
;;   (with-slots (buffer head-mode head-buffer tail-mode tail-buffer) obj
;;     (pcase (list type head-mode tail-mode)
;;       (`(body body ,(or `nil `body))
;;        (setq buffer buff
;;              head-buffer buff
;;              tail-buffer buff))
;;       (`(body ,_ body)
;;        (setq buffer buff
;;              tail-buffer buff))
;;       (`(body ,_ ,_ )
;;        (setq buffer buff))
;;       (`(head ,_ ,(or `nil `head))
;;        (setq head-buffer buff
;;              tail-buffer buff))
;;       (`(head ,_ ,_)
;;        (setq head-buffer buff))
;;       (`(tail ,_ ,(or `nil `head))
;;        (setq tail-buffer buff
;;              head-buffer buff))
;;       (`(tail ,_ ,_)
;;        (setq tail-buffer buff))
;;       (_ (error "type must be one of 'body 'head and 'tail")))))

;; a literal transcript of the pcase above
(defun pm--set-submode-buffer (obj type buff)
  (with-slots (-buffer head-mode -head-buffer tail-mode -tail-buffer) obj
    (cond
     ((and (eq type 'body)
           (eq head-mode 'body)
           (or (null tail-mode)
               (eq tail-mode 'body)))
      (setq -buffer buff
            -head-buffer buff
            -tail-buffer buff))
     ((and (eq type 'body)
           (eq tail-mode 'body))
      (setq -buffer buff
            -tail-buffer buff))
     ((eq type 'body)
      (setq -buffer buff))
     ((and (eq type 'head)
           (or (null tail-mode)
               (eq tail-mode 'head)))
      (setq -head-buffer buff
            -tail-buffer buff))
     ((eq type 'head)
      (setq -head-buffer buff))
     ((and (eq type 'tail)
           (or (null tail-mode)
               (eq tail-mode 'head)))
      (setq -tail-buffer buff
            -head-buffer buff))
     ((eq type 'tail)
      (setq -tail-buffer buff))
     (t (error "type must be one of 'body 'head and 'tail")))))

(defun pm--get-submode-mode (obj type)
  (with-slots (mode head-mode tail-mode) obj
    (cond ((or (eq type 'body)
               (and (eq type 'head)
                    (eq head-mode 'body))
               (and (eq type 'tail)
                    (or (eq tail-mode 'body)
                        (and (null tail-mode)
                             (eq head-mode 'body)))))
           (oref obj :mode))
          ((or (and (eq type 'head)
                    (eq head-mode 'base))
               (and (eq type 'tail)
                    (or (eq tail-mode 'base)
                        (and (null tail-mode)
                             (eq head-mode 'base)))))
           (oref (oref pm/config -basemode) :mode))
          ((eq type 'head)
           (oref obj :head-mode))
          ((eq type 'tail)
           (oref obj :tail-mode))
          (t (error "type must be one of 'head 'tail 'body")))))

(defun pm--create-submode-buffer-maybe (submode type)
  ;; assumes pm/config is set
  (let ((mode (pm--get-submode-mode submode type)))
    (or (pm--get-indirect-buffer-of-mode mode)
        (let ((buff (pm--create-indirect-buffer mode)))
          (with-current-buffer  buff
            (setq pm/submode submode)
            (setq pm/type type)
            (pm--setup-buffer)
            (funcall (oref pm/config :minor-mode))
            buff)))))

(defun pm--get-mode-symbol-from-name (str)
  "Gues and return mode function.
Return major mode function constructed from STR by appending
'-mode' if needed. If the constructed symbol is not a function
return an error."
  (let ((mname (if (string-match-p "-mode$" str)
                   str
                 (concat str "-mode"))))
    (pm--get-available-mode (intern mname))))

(defun pm--oref-with-parents (object slot)
  "Merge slots SLOT from the OBJECT and all its parent instances."
  (let (VALS)
    (while object
      (setq VALS (append (and (slot-boundp object slot) ; don't cascade
                              (eieio-oref object slot))
                         VALS)
            object (and (slot-boundp object :parent-instance)
                        (oref object :parent-instance))))
    VALS))

(defun pm--abrev-names (list abrev-regexp)
  "Abreviate names in LIST by replacing abrev-regexp with empty
string."
  (mapcar (lambda (nm)
            (let ((str-nm (if (symbolp nm)
                              (symbol-name nm)
                            nm)))
              (propertize (replace-regexp-in-string abrev-regexp "" str-nm)
                          :orig str-nm)))
          list))

(defun pm--put-hist (key val)
  (oset pm/config -hist
        (plist-put (oref pm/config -hist) key val)))

(defun pm--get-hist (key)
  (plist-get (oref pm/config -hist) key))

(defun pm--comment-region (beg end)
  ;; mark as syntactic comment
  (when (> end 1)
    (with-silent-modifications
      (let ((beg (or beg (region-beginning)))
            (end (or end (region-end))))
        (let ((ch-beg (char-after beg))
              (ch-end (char-before end)))
          (add-text-properties beg (1+ beg)
                               (list 'syntax-table (cons 11 ch-beg)
                                     'rear-nonsticky t
                                     'polymode-comment 'start))
          (add-text-properties (1- end) end
                               (list 'syntax-table (cons 12 ch-end)
                                     'rear-nonsticky t
                                     'polymode-comment 'end)))))))

(defun pm--uncomment-region (beg end)
  ;; remove all syntax-table properties. Should not cause any problem as it is
  ;; always used before font locking
  (when (> end 1)
    (with-silent-modifications
      (let ((props '(syntax-table nil rear-nonsticky nil polymode-comment nil)))
        (remove-text-properties beg end props)
        ;; (remove-text-properties beg (1+ beg) props)
        ;; (remove-text-properties end (1- end) props)
        ))))

(defun pm--run-command (command sentinel buff-name message)
  "Run command interactively.
Run command in a buffer (in comint-shell-mode) so that it accepts
user interaction."
  ;; simplified version of TeX-run-TeX
  (require 'comint)
  (let* ((buffer (get-buffer-create buff-name))
         (process nil)
         (command-buff (current-buffer))
         (ofile pm--output-file))
    (with-current-buffer buffer
      (setq pm--process-buffer t)
      (read-only-mode -1)
      (erase-buffer)
      (insert message)
      (comint-exec buffer buff-name shell-file-name nil
                   (list shell-command-switch command))
      (comint-mode)
      (setq process (get-buffer-process buffer))
      (set-process-sentinel process sentinel)
      ;; communicate with sentinel
      (set (make-local-variable 'pm--output-file) ofile)
      (set (make-local-variable 'pm--input-buffer) command-buff)
      (set-marker (process-mark process) (point-max)))
    nil))

(defun pm--run-command-sentinel (process name message)
  (let ((buff (process-buffer process)))
    (with-current-buffer buff
      ;; fixme: remove this later
      (sit-for 1)
      (goto-char (point-min))
      (let ((case-fold-search t))
        (if (not (re-search-forward "error" nil 'no-error))
            pm--output-file
          (display-buffer (current-buffer))
          (error "Bumps while %s (%s)" message name))))))


;;; COMPATIBILITY and FIXES
(defun pm--flyspel-dont-highlight-in-submodes (beg end poss)
  (or (get-text-property beg 'chunkmode)
      (get-text-property beg 'chunkmode)))

(defvar object-name)
(defun pm--object-name (object)
  (if (fboundp 'eieio--object-name)
      (eieio--object-name object)
    (aref object object-name)))


;;; DEBUG STUFF
(defun pm--map-over-spans-highlight ()
  (interactive)
  (pm/map-over-spans (lambda ()
                       (let ((start (nth 1 *span*))
                             (end (nth 2 *span*)))
                         (ess-blink-region start end)
                         (sit-for 1)))
                     (point-min) (point-max)))

(defun pm--highlight-span (&optional hd-matcher tl-matcher)
  (interactive)
  (let* ((hd-matcher (or hd-matcher (oref pm/submode :head-reg)))
         (tl-matcher (or tl-matcher (oref pm/submode :tail-reg)))
         (span (pm--span-at-point hd-matcher tl-matcher)))
    (ess-blink-region (nth 1 span) (nth 2 span))
    (message "%s" span)))

(defun pm--run-over-check ()
  (interactive)
  (goto-char (point-min))
  (let ((start (current-time))
        (count 1))
    (polymode-select-buffer)
    (while (< (point) (point-max))
      (setq count (1+ count))
      (forward-char)
      (polymode-select-buffer))
    (let ((elapsed  (float-time (time-subtract (current-time) start))))
      (message "elapsed: %s  per-char: %s" elapsed (/ elapsed count)))))

(provide 'polymode-common)

