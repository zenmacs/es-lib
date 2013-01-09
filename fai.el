(defvar fai-indent-function 'fai-indent-line-maybe
  "Function to call after ever change, when")
(defvar fai-indentable-line-p-function (es-constantly t)
  "For mode-specifc cusomizations.")
(defvar fai-after-change-indentation t
  "Whether to reindent after every change.
Useful when you want to keep the keymap and cursor repositioning.")
(defvar fai-indent-limit 20
  "Maximum number of lines for after-change indentation.")

(es-define-buffer-local-vars
 fai-change-flag nil)

(defun fai-indent-line-maybe ()
  "\(indent-according-to-mode\) when `fai-indentable-line-p-function' returns non-nil."
  (when (and fai-mode
             (not (eq indent-line-function 'insert-tab))
             (funcall fai-indentable-line-p-function))
    (indent-according-to-mode)))

(defun fai-indent-forward ()
  "Indent current line, and `fai-indent-limit' lines afterwards."
  (save-excursion
    (fai-indent-line-maybe)
    (dotimes (ignore fai-indent-limit)
      (forward-line)
      (fai-indent-line-maybe))))

(defun fai-indent-defun ()
  "Indents current defun, if it is smaller than `fai-indent-limit'.
Otherwise `fai-indent-forward'."
  (let (init-pos
        line-end-distance)
    (condition-case nil
        (save-excursion
          (setq line-end-distance)
          (beginning-of-defun)
          (setq init-pos (point))
          (forward-sexp)
          (when (> (1+ (- (line-number-at-pos)
                          (line-number-at-pos init-pos)))
                   fai-indent-limit)
            (error "defun too long"))
          (goto-char init-pos)
          (indent-pp-sexp))
      (error (fai-indent-forward)))
    (fai-correct-position-this)))

(defun fai-indented-yank (&optional dont-indent)
  (interactive)
  (flet ((message (&rest ignore)))
    (when (region-active-p)
      (delete-region (point) (mark)))
    (let ((starting-point (point))
          end-distance
          line)
      (yank)
      (setq end-distance (- (line-end-position) (point))
            line (line-number-at-pos))
      (unless (or dont-indent
                  (> (- (point) starting-point)
                     4000))
        (indent-region starting-point (point)))
      (when (bound-and-true-p font-lock-mode)
        (font-lock-fontify-region starting-point (point)))
      (goto-line line)
      (goto-char (- (line-end-position) end-distance)))))

(defun fai-mouse-yank (event &optional dont-indent)
  (interactive "e")
  (if (region-active-p)
      (let ((reg-beg (region-beginning))
            (reg-end (region-end)))
        (mouse-set-point event)
        (when (and (<= reg-beg (point))
                   (<= (point) reg-end))
          (delete-region reg-beg reg-end)
          (goto-char reg-beg)))
      (progn
        (mouse-set-point event)
        (deactivate-mark)))
  (fai-indented-yank dont-indent))

(defun fai-mouse-yank-dont-indent (event)
  (interactive "e")
  (fai-mouse-yank event t))

(defun fai-delete (&optional from-backspace)
  (interactive)
  (if (region-active-p)
      (delete-region (point) (mark))
      ;; The following functionality might overlap;
      (if (>= (point)
              (es-visible-end-of-line))
          (progn
            (delete-region (point) (1+ (line-end-position)))
            (when (and (fixup-whitespace)
                       (not from-backspace))
              (backward-char)))
          (delete-char 1))))

(defun fai-backspace ()
  (interactive)
  (cond ( (and (not (bound-and-true-p autopair-mode))
               (es-point-between-pairs-p))
          (delete-char 1)
          (delete-char -1))
        ( (region-active-p)
          (delete-region (point) (mark)))
        ( (<= (current-column)
              (current-indentation))
          (previous-logical-line)
          (end-of-line)
          (fai-delete t))
        ( (bound-and-true-p paredit-mode)
          (paredit-backward-delete))
        ( t (backward-delete-char 1))))

(defun fai-open-line ()
  (interactive)
  (let ((was-at-eol (>= (point) (es-visible-end-of-line))))
    (save-excursion
      (newline))
    (save-excursion
      (forward-char)
      (fai-indent-line-maybe))))

(defun* fai-newline-and-indent ()
  (interactive)
  (when (and (not (region-active-p))
             (equal (char-before) ?{ )
             (equal (char-after) ?} ))
    (newline)
    (save-excursion
      (newline))
    (indent-according-to-mode)
    (save-excursion
      (forward-char)
      (indent-according-to-mode))
    (return-from fai-newline-and-indent))
  (when (region-active-p)
    (delete-region (point) (mark)))
  (newline)
  (fai-indent-line-maybe)
  (when (memq major-mode '(nxml-mode web-mode))
    (save-excursion
      (forward-line -1)
      (indent-according-to-mode))))

(defun fai-correct-position-this ()
  "Go back to indentation, if point is before indentation."
  (let ((indentation-beginning (es-indentation-end-pos)))
    (when (< (point) indentation-beginning)
      (goto-char indentation-beginning))))

(defun fai-before-change-function (&rest ignore)
  "Change tracking."
  (setq fai-change-flag t))

(defun* fai-post-command-hook ()
  "First key stroke tracking, cursor correction"
  (unless fai-mode
    (return-from fai-post-command-hook))
  (let* (( last-input-structural
           (member last-input-event
                   (mapcar 'string-to-char
                           (list "(" ")" "[" "]" "{" "}" "," ";" " "))))
         ( first-keystroke
           (and (eq this-command 'self-insert-command)
                (or last-input-structural
                    (not (eq last-command 'self-insert-command))))))
    ;; Correct position
    (when (and (es-neither (region-active-p)
                           (bound-and-true-p cua--rectangle)
                           (bound-and-true-p multiple-cursors-mode))
               (> (es-indentation-end-pos) (point)))
      (cond ( (memq this-command '(backward-char left-char))
              (end-of-line 0))
            ( (memq this-command
                    '(forward-char right-char
                      previous-line next-line))
              (back-to-indentation))))
    ;; It won't indent if corrected
    (when (and fai-after-change-indentation
               fai-change-flag
               (buffer-modified-p)
               (or first-keystroke
                   (not (memq
                         this-command
                         '(save-buffer
                           delete-horizontal-space
                           undo
                           undo-tree-undo
                           undo-tree-redo
                           quoted-insert
                           backward-paragraph
                           self-insert-command))))
               (not (region-active-p)))
      (funcall fai-indent-function))
    (setq fai-change-flag nil)))

(defun fai--init ()
  (eval-after-load "multiple-cursors-core"
    '(pushnew 'fai-mode mc/unsupported-minor-modes))
  (eval-after-load "paredit"
    '(es-define-keys fai-mode-map
      [remap paredit-forward-delete] 'fai-delete
      [remap paredit-backward-delete] 'fai-backspace))
  (eval-after-load "cua-base"
    (define-key cua--region-keymap [remap delete-char]
      (lambda ()
        (interactive)
        (if fai-mode
            (fai-delete)
            (cua-delete-region)))))
  (setq inhibit-modification-hooks nil)
  (pushnew 'fai-before-change-function before-change-functions)
  (add-hook 'post-command-hook 'fai-post-command-hook t t)
  (es-define-keys fai-mode-map
    [mouse-2] 'fai-mouse-yank
    [remap cua-paste] 'fai-indented-yank
    [remap yank] 'fai-indented-yank
    [remap newline] 'fai-newline-and-indent
    [remap open-line] 'fai-open-line
    [remap delete-char] 'fai-delete
    [remap forward-delete] 'fai-delete
    [remap backward-delete-char-untabify] 'fai-backspace
    [remap backward-delete-char] 'fai-backspace
    ))

(define-minor-mode fai-mode
    "Fuchikoma Automatic Indentation"
  nil " fai" (make-sparse-keymap)
  (if fai-mode
      (fai--init)))

(provide 'fai)