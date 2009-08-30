(defpackage :doc-skeleton
  (:use :cl :gtk :gdk :gobject :iter :c2mop :glib)
  (:export :widget-skeleton
           :chapter-skeleton
           :*gtk-widgets*
           :all-gtk-widgets))

(in-package :doc-skeleton)

(defun chapter-skeleton (output widgets &key use-refs (section "section"))
  (cond
    ((stringp output) (with-open-file (stream output :direction :output :if-exists :supersede)
                        (chapter-skeleton stream widgets :use-refs use-refs)))
    ((null output) (with-output-to-string (stream)
                     (chapter-skeleton stream widgets :use-refs use-refs)))
    ((or (eq t output) (streamp output))
     (format output "@menu~%")
     (iter (for w in widgets)
           (format output "* ~A::~%" (string-downcase (symbol-name w))))
     (format output "@end menu~%~%")
     (iter (for w in widgets)
           (write-string (widget-skeleton w :section section :use-refs use-refs) output)
           (format output "~%~%")))))

(defparameter *gtk-widgets* '(about-dialog accel-label alignment arrow
  aspect-frame assistant bin box button button-box calendar cell-view
  check-button check-menu-item color-button color-selection
  color-selection-dialog combo-box combo-box-entry container curve
  dialog drawing-area entry event-box expander file-chooser-button
  file-chooser-dialog file-chooser-widget fixed font-button
  font-selection font-selection-dialog frame gamma-curve gtk-window
  h-box h-button-box h-paned h-ruler h-s-v h-scale h-scrollbar
  h-separator handle-box icon-view image image-menu-item input-dialog
  invisible item label layout link-button menu menu-bar menu-item
  menu-shell menu-tool-button message-dialog misc notebook
  old-editable paned plug progress progress-bar radio-button
  radio-menu-item radio-tool-button range recent-chooser-dialog
  recent-chooser-menu recent-chooser-widget ruler scale scale-button
  scrollbar scrolled-window separator separator-menu-item
  separator-tool-item socket spin-button statusbar table
  tearoff-menu-item text text-view toggle-button toggle-tool-button
  tool-button tool-item toolbar tree tree-item tree-view v-box
  v-button-box v-paned v-ruler v-scale v-scrollbar v-separator
  viewport volume-button widget))

(defun all-gtk-widgets ()
  (sort (iter (for symbol in-package (find-package :gtk) :external-only t)
              (for class = (find-class symbol nil))
              (when (and class (subclassp class (find-class 'gtk:widget)))
                (collect symbol)))
        #'string<))

;; (widget-skeleton widget &key (sectioning-command "section"))
;; returns the texinfo string for widget (a symbol or class)
;; Template:
;; 
;; @node $WIDGET
;; @$SECTIONING-COMMAND $WIDGET
;;
;; @Class $WIDGET
;; 
;; Superclass: $(direct-superclass WIDGET)
;;
;; Interfaces: $(direct-interface widget)
;;
;; Slots:
;; @itemize
;; $(for each slot)
;; @item @anchor{slot.$widget.$slot}$slot. Type: $(slot-type slot). Accessor: $(slot-accessor slot). $(when (constructor-only slot) "Contructor-only slot.")
;; $(end for)
;; @end itemize
;;
;; Signals:
;; @itemize
;; $(for each signal)
;; @item @anchor{signal.$widget.$signal}"$signal". Signature: Type1 Arg1, .., Typen Argn => return-type. Options: $(signal-options)
;; $(end for)
;; @end itemize

(defvar *use-refs* t)

(defun widget-skeleton (widget &key (section "section") (use-refs nil))
  (unless (typep widget 'class) (setf widget (find-class widget)))
  (with-output-to-string (stream)
    (let ((*print-case* :downcase)
          (*package* (symbol-package (class-name widget)))
          (*print-circle* nil)
          (*use-refs* use-refs))
      (format stream "@node ~A~%" (class-name widget))
      (format stream "@~A ~A~%" section (class-name widget))
      (format stream "@Class ~A~%" (class-name widget))
      (format stream "Superclass:")
      (iter (for super in (class-direct-superclasses widget))
            (unless (and (typep super 'gobject-class) (gobject::gobject-class-interface-p super))
              (format stream " @code{~A}" (class-name super))))
      (format stream "~%~%")
      (widget-slots stream widget)
      (format stream "~%~%")
      (widget-signals stream widget)
      (format stream "~%~%")
      (widget-child-properties stream widget))))

(defun widget-slots (stream widget)
  (format stream "Slots:~%")
  (format stream "@itemize~%")
  (iter (for slot in (class-direct-slots widget))
        (when (typep slot 'gobject::gobject-direct-slot-definition)
          (format stream "@item @anchor{slot.~A.~A}~A. Type: ~A. Accessor: ~A."
                  (class-name widget) (slot-definition-name slot)
                  (slot-definition-name slot)
                  (slot-type slot)
                  (slot-accessor slot))
          (case (classify-slot-readability widget slot)
            (:write-only (format stream " Write-only."))
            (:read-only (format stream " Read-only.")))
          (format stream "~%")))
  (format stream "@end itemize~%"))

(defun widget-signals (stream widget)
  (let ((g-type (gobject::gobject-class-g-type-name widget)))
    (unless (string= g-type (gobject::gobject-class-g-type-name (first (class-direct-superclasses widget))))
      (format stream "Signals:~%")
      (format stream "@itemize~%")
  ;; @item @anchor{signal.$widget.$signal}"$signal". Signature: Type1 Arg1, .., Typen Argn => return-type. Options: $(signal-options)
      (iter (for signal in (type-signals g-type))
            (format stream "@item @anchor{signal.~A.~A}\"~A\". Signature: ~A. Options: ~A."
                    (class-name widget)
                    (signal-info-name signal)
                    (signal-info-name signal)
                    (signal-signature signal)
                    (signal-options signal))
            (format stream "~%"))
      (format stream "@end itemize~%"))))

(defun widget-child-properties (stream widget)
  (let ((g-type (gobject::gobject-class-g-type-name widget)))
    (when (g-type-is-a g-type "GtkContainer")
      (unless (string= g-type (gobject::gobject-class-g-type-name (first (class-direct-superclasses widget))))
        (let ((props (gtk::container-class-child-properties g-type)))
          (when props
            (format stream "Child properties:~%")
            (format stream "@itemize~%")
            ;; @item @anchor{signal.$widget.$signal}"$signal". Signature: Type1 Arg1, .., Typen Argn => return-type. Options: $(signal-options)
            (iter (for prop in props)
                  (for accessor = (format nil "~A-child-~A"
                                      (string-downcase (symbol-name (class-name widget)))
                                      (g-class-property-definition-name prop)))
                  (format stream "@item @anchor{childprop.~A.~A}~A. Type: ~A. Accessor: ~A."
                          (string-downcase (symbol-name (class-name widget)))
                          (g-class-property-definition-name prop)
                          (g-class-property-definition-name prop)
                          (type-string (g-class-property-definition-type prop))
                          accessor)
                  (format stream "~%"))
            (format stream "@end itemize~%")))))))

(defun signal-signature (s)
  (with-output-to-string (stream)
    (format stream "(instance ~A)" (type-string (signal-info-owner-type s)))
    (iter (for type in (signal-info-param-types s))
          (for counter from 1)
          (format stream ", (arg-~A ~A)" counter (type-string type)))
    (format stream " @result{} ~A" (type-string (signal-info-return-type s)))))

(defun signal-options (s)
  (format nil "~{~A~^, ~}"(signal-info-flags s)))

(defun slot-type (slot)
  (let ((type (gobject::gobject-direct-slot-definition-g-property-type slot)))
    (type-string type)))

(defun type-string (type)
  (typecase type
    (string (type-string-s type))
    (t (type-string-f type))))

(defun ensure-list (x) (if (listp x) x (list x)))

(defun type-string-f (type)
  (let ((l (ensure-list type)))
    (case (first l)
      ((:string glib:g-string) "@code{string}")
      ((:int :uint :long :ulong :char :uchar :int64 :uint64) "@code{integer}")
      ((:boolean :bool) "@code{boolean}")
      (g-object (if (second l)
                    (format-ref (string-downcase (symbol-name (second l))))
                    "@ref{g-object}"))
      (g-boxed-foreign (format-ref (string-downcase (symbol-name (second l)))))
      ((nil) "????")
      ((glist gslist) (format nil "list of ~A" (type-string-f (second l))))
      (t (if (symbolp type)
             (format-ref type)
             (format-ref l))))))

(defun type-string-s (type)
  (cond
    ((g-type= type +g-type-string+) "@code{string}")
    ((g-type= type +g-type-boolean+) "@code{boolean}")
    ((g-type= type +g-type-float+) "@code{single-float}")
    ((g-type= type +g-type-double+) "@code{double-float}")
    ((or (g-type= type +g-type-int+)
         (g-type= type +g-type-uint+)
         (g-type= type +g-type-char+)
         (g-type= type +g-type-uchar+)
         (g-type= type +g-type-long+)
         (g-type= type +g-type-ulong+)
         (g-type= type +g-type-int64+)
         (g-type= type +g-type-uint64+)
         (g-type= type +g-type-uint64+)) "@code{integer}")
    ((g-type= type +g-type-float+) "@code{single-float}")
    ((g-type-is-a type +g-type-enum+) (enum-string type))
    ((g-type-is-a type +g-type-flags+) (flags-string type))
    ((g-type-is-a type +g-type-object+) (object-string type))
    ((g-type-is-a type +g-type-boxed+) (boxed-string type))
    (t type)))

(defun format-ref (s)
  (if *use-refs*
      (format nil "@ref{~A}" s)
      (format nil "@code{~A}" s)))

(defun flags-string (type)
  (let ((flags (gobject::registered-flags-type (g-type-string type))))
    (if flags
        (format-ref flags)
        (format nil "@code{~A}" (g-type-string type)))))

(defun enum-string (type)
  (let ((enum (gobject::registered-enum-type (g-type-string type))))
    (if enum
        (format-ref enum)
        (format nil "@code{~A}" (g-type-string type)))))

(defun object-string (type)
  (let ((class (gobject::registered-object-type-by-name (g-type-string type))))
    (if class
        (format-ref class)
        (format nil "@code{~A}" (g-type-string type)))))

(defun boxed-string (type)
  (let ((boxed (ignore-errors (gobject::get-g-boxed-foreign-info-for-gtype (g-type-string type)))))
    (if boxed
        (format-ref (gobject::g-boxed-info-name boxed))
        (format nil "@code{~A}" (g-type-string type)))))

(defmethod classify-slot-readability (class (slot gobject::gobject-property-direct-slot-definition))
  (let* ((g-type (gobject::gobject-class-g-type-name class))
         (property-name (gobject::gobject-property-direct-slot-definition-g-property-name slot))
         (prop (class-property-info g-type property-name))
         (readable (g-class-property-definition-readable prop))
         (writable (g-class-property-definition-writable prop)))
    (cond
      ((and readable writable) :normal)
      ((not readable) :write-only)
      ((not writable) :read-only)
      (t :bad))))

(defmethod classify-slot-readability (class (slot gobject::gobject-fn-direct-slot-definition))
  (let ((readable (gobject::gobject-fn-direct-slot-definition-g-getter-name slot))
        (writable (gobject::gobject-fn-direct-slot-definition-g-setter-name slot)))
    (cond
      ((and readable writable) :normal)
      ((not readable) :write-only)
      ((not writable) :read-only)
      (t :bad))))

(defun slot-accessor (slot)
  (let* ((readers (slot-definition-readers slot))
         (writers (mapcar #'second (slot-definition-writers slot)))
         (combined (union readers writers))
         (accessor (first combined)))
    (if accessor
        (format nil "@anchor{~A}@code{~A}" accessor accessor)
        (format nil "None"))))