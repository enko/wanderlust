;;; elmo-map.el -- A ELMO folder class with message number mapping.

;; Copyright (C) 2000 Yuuichi Teranishi <teranisi@gohome.org>

;; Author: Yuuichi Teranishi <teranisi@gohome.org>
;; Keywords: mail, net news

;; This file is part of ELMO (Elisp Library for Message Orchestration).

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.
;;

;;; Commentary:
;; Folders which do not have unique message numbers but unique message names
;; should inherit this folder.

;;; Code:
;; 
(require 'elmo)
(require 'elmo-msgdb)

(eval-when-compile (require 'cl))

(eval-and-compile
  ;; location-hash: location->number mapping
  ;; number-hash:   number->location mapping
  (luna-define-class elmo-map-folder (elmo-folder)
		     (location-alist number-max location-hash))
  (luna-define-internal-accessors 'elmo-map-folder))

(defun elmo-map-folder-numbers-to-locations (folder numbers)
  (let (locations pair)
    (dolist (number numbers)
      (if (setq pair (elmo-get-hash-val
		      (concat "#" (int-to-string number))
		      (elmo-map-folder-location-hash-internal folder)))
	  (setq locations (cons (cdr pair) locations))))
    (nreverse locations)))

(defun elmo-map-folder-locations-to-numbers (folder locations)
  (let (numbers pair)
    (dolist (location locations)
      (if (setq pair (elmo-get-hash-val
		      location
		      (elmo-map-folder-location-hash-internal folder)))
	  (setq numbers (cons (car pair) numbers))))
    (nreverse numbers)))

(luna-define-generic elmo-map-folder-list-message-locations (folder)
  "Return a location list of the FOLDER.")

(luna-define-generic elmo-map-folder-unmark-important (folder locations)
  "")

(luna-define-generic elmo-map-folder-mark-as-important (folder locations)
  "")

(luna-define-generic elmo-map-folder-unmark-read (folder locations)
  "")

(luna-define-generic elmo-map-folder-mark-as-read (folder locations)
  "")

(luna-define-generic elmo-map-message-fetch (folder location
						    strategy
						    &optional
						    section
						    outbuf unseen)
  "")

(luna-define-generic elmo-map-folder-list-unreads (folder)
  "")

(luna-define-generic elmo-map-folder-list-importants (folder)
  "")

(luna-define-generic elmo-map-folder-delete-messages (folder locations)
  "")

(luna-define-method elmo-folder-status ((folder elmo-map-folder))
  (elmo-folder-open-internal folder)
  (prog1
      (let ((numbers (mapcar
		      'car
		      (elmo-map-folder-location-alist-internal folder))))
	(cons (elmo-max-of-list numbers)
	      (length numbers)))
    ;; No save.
    (elmo-folder-close-internal folder)))

(defun elmo-map-message-number (folder location)
  "Return number of the message in the FOLDER with LOCATION."
  (car (elmo-get-hash-val
	location
	(elmo-map-folder-location-hash-internal folder))))

(defun elmo-map-message-location (folder number)
  "Return location of the message in the FOLDER with NUMBER."
  (cdr (elmo-get-hash-val
	(concat "#" (int-to-string number))
	(elmo-map-folder-location-hash-internal folder))))

(luna-define-method elmo-folder-pack-number ((folder elmo-map-folder))
  (let* ((msgdb (elmo-folder-msgdb-internal folder))
	 (old-number-alist (elmo-msgdb-get-number-alist msgdb))
	 (old-overview (elmo-msgdb-get-overview msgdb))
	 (old-mark-alist (elmo-msgdb-get-mark-alist msgdb))
	 (old-location (elmo-map-folder-location-alist-internal folder))
	 old-number overview number-alist mark-alist location
	 mark (number 1))
    (setq overview old-overview)
    (while old-overview
      (setq old-number
	    (elmo-msgdb-overview-entity-get-number (car old-overview)))
      (elmo-msgdb-overview-entity-set-number (car old-overview) number)
      (setq number-alist
	    (cons (cons number (cdr (assq old-number old-number-alist)))
		  number-alist))
      (when (setq mark (cadr (assq old-number old-mark-alist)))
	(setq mark-alist
	      (elmo-msgdb-mark-append
	       mark-alist number mark)))
      (setq location
	    (cons (cons number
			(elmo-map-message-location folder old-number))
		  location))
      (setq number (1+ number))
      (setq old-overview (cdr old-overview)))
    (elmo-map-folder-location-setup folder (nreverse location))
    (elmo-folder-set-msgdb-internal
     folder
     (list overview
	   (nreverse number-alist)
	   (nreverse mark-alist)
	   (elmo-msgdb-make-overview-hashtb overview)))))

(defun elmo-map-folder-location-setup (folder locations)
  (elmo-map-folder-set-location-alist-internal
   folder
   locations)
  (elmo-map-folder-set-location-hash-internal
   folder (elmo-make-hash
	   (* 2 (length locations))))
  (elmo-map-folder-set-number-max-internal folder 0)
  ;; Set number-max and hashtables.
  (dolist (location-cons locations)
    (if (< (elmo-map-folder-number-max-internal folder)
	   (car location-cons))
	(elmo-map-folder-set-number-max-internal folder (car location-cons)))
    (elmo-set-hash-val (cdr location-cons)
		       location-cons
		       (elmo-map-folder-location-hash-internal folder))
    (elmo-set-hash-val (concat "#" (int-to-string (car location-cons)))
		       location-cons
		       (elmo-map-folder-location-hash-internal folder))))

(defun elmo-map-folder-update-locations (folder locations)
  ;; A subroutine to make location-alist.
  ;; location-alist is existing location-alist.
  ;; locations is the newest locations.
  (let* ((location-alist (elmo-map-folder-location-alist-internal folder))
	 (locations-in-db (mapcar 'cdr location-alist))
	 new-locs new-alist deleted-locs pair i)
    (setq new-locs
	  (elmo-delete-if (function
			   (lambda (x) (member x locations-in-db)))
			  locations))
    (setq deleted-locs
	  (elmo-delete-if (function
			   (lambda (x) (member x locations)))
			  locations-in-db))
    (dolist (location deleted-locs)
      (setq location-alist
	    (delq (setq pair
			(elmo-get-hash-val
			 location
			 (elmo-map-folder-location-hash-internal
			  folder)))
		  location-alist))
      (elmo-clear-hash-val (concat "#" (int-to-string (car pair)))
			   (elmo-map-folder-location-hash-internal
			    folder))
      (elmo-clear-hash-val location
			   (elmo-map-folder-location-hash-internal
			    folder)))
    (setq i (elmo-map-folder-number-max-internal folder))
    (dolist (location new-locs)
      (setq i (1+ i))
      (elmo-map-folder-set-number-max-internal folder i)
      (setq new-alist (cons (setq pair (cons i location)) new-alist))
      (setq new-alist (nreverse new-alist))
      (elmo-set-hash-val (concat "#" (int-to-string i))
			 pair
			 (elmo-map-folder-location-hash-internal
			  folder))
      (elmo-set-hash-val location
			 pair
			 (elmo-map-folder-location-hash-internal
			  folder)))
    (setq location-alist (nconc location-alist new-alist))
    (elmo-map-folder-set-location-alist-internal folder location-alist)))

(luna-define-method elmo-folder-open-internal ((folder elmo-map-folder))
  (elmo-map-folder-location-setup
   folder 
   (elmo-msgdb-location-load (elmo-folder-msgdb-path folder)))
  (elmo-map-folder-update-locations
   folder
   (elmo-map-folder-list-message-locations folder)))

(luna-define-method elmo-folder-commit :after ((folder elmo-map-folder))
  (when (elmo-folder-persistent-p folder)
    (elmo-msgdb-location-save (elmo-folder-msgdb-path folder)
			      (elmo-map-folder-location-alist-internal
			       folder))))

(luna-define-method elmo-folder-close-internal ((folder elmo-map-folder))
  (elmo-map-folder-set-location-alist-internal folder nil)
  (elmo-map-folder-set-location-hash-internal folder nil))
  
(luna-define-method elmo-folder-check ((folder elmo-map-folder))
  (elmo-map-folder-update-locations
   folder
   (elmo-map-folder-list-message-locations folder)))

(luna-define-method elmo-folder-list-messages-internal
  ((folder elmo-map-folder))
  (mapcar 'car (elmo-map-folder-location-alist-internal folder)))

(luna-define-method elmo-folder-unmark-important ((folder elmo-map-folder)
						  numbers)
  (elmo-map-folder-unmark-important
   folder
   (elmo-map-folder-numbers-to-locations folder numbers)))

(luna-define-method elmo-folder-mark-as-important ((folder elmo-map-folder)
						   numbers)
  (elmo-map-folder-mark-as-important
   folder
   (elmo-map-folder-numbers-to-locations folder numbers)))

(luna-define-method elmo-folder-unmark-read ((folder elmo-map-folder)
					     numbers)
  (elmo-map-folder-unmark-read
   folder
   (elmo-map-folder-numbers-to-locations folder numbers)))

(luna-define-method elmo-folder-mark-as-read ((folder elmo-map-folder) numbers)
  (elmo-map-folder-mark-as-read
   folder
   (elmo-map-folder-numbers-to-locations folder numbers)))

(luna-define-method elmo-message-fetch ((folder elmo-map-folder) number
					strategy section outbuf unread)
  (elmo-map-message-fetch
   folder
   (elmo-map-message-location folder number)
   strategy section outbuf unread))

(luna-define-method elmo-folder-list-unreads-internal
  ((folder elmo-map-folder) unread-marks)
  (elmo-map-folder-locations-to-numbers
   folder
   (elmo-map-folder-list-unreads folder)))

(luna-define-method elmo-folder-list-importants-internal
  ((folder elmo-map-folder) important-mark)
  (elmo-map-folder-locations-to-numbers
   folder
   (elmo-map-folder-list-importants folder)))

(luna-define-method elmo-folder-delete-messages ((folder elmo-map-folder)
						 numbers)
  (elmo-map-folder-delete-messages
   folder
   (elmo-map-folder-numbers-to-locations folder numbers))
  (dolist (number numbers)
    (elmo-map-folder-set-location-alist-internal
     folder
     (delq (elmo-get-hash-val
	    (concat "#" (int-to-string number))
	    (elmo-map-folder-location-hash-internal
	     folder))
	   (elmo-map-folder-location-alist-internal folder))))
  t) ; success
  

(require 'product)
(product-provide (provide 'elmo-map) (require 'elmo-version))

;;; elmo-map.el ends here
