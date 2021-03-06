var mn = mn || {};
mn.components = mn.components || {};
mn.components.MnSearchField =
  (function (Rx) {
    "use strict";

    mn.core.extend(MnSearchFieldComponent, mn.core.MnEventableComponent);

    MnSearchFieldComponent.annotations = [
      new ng.core.Component({
        selector: "mn-search-field",
        templateUrl: 'app-new/mn-search-field.html',
        inputs: [
          "mnFormGroup",
          "mnFocusStream",
          "mnClearStream",
          "mnPlaceholder"
        ],
        changeDetection: ng.core.ChangeDetectionStrategy.OnPush
      })
    ];

    MnSearchFieldComponent.prototype.clearSearchTerm = clearSearchTerm;
    MnSearchFieldComponent.prototype.ngOnInit = ngOnInit;

    return MnSearchFieldComponent;

    function MnSearchFieldComponent() {
      mn.core.MnEventableComponent.call(this);
    }

    function ngOnInit() {
      this.onClearClick = new Rx.Subject();
      this.mnFocusStream = this.mnFocusStream || Rx.Observable.never();
      this.mnClearStream = this.mnClearStream || Rx.Observable.never();

      Rx.merge(this.onClearClick, this.mnClearStream)
        .pipe(Rx.operators.takeUntil(this.mnOnDestroy))
        .subscribe(this.clearSearchTerm.bind(this));

      this.isSearchPresent =
        this.mnFormGroup.valueChanges.pipe(
          Rx.operators.pluck("searchTerm"),
          Rx.operators.map(Boolean),
          Rx.operators.multicast(function () {return new Rx.ReplaySubject(1);}),Rx.operators.refCount()
        );

    }

    function clearSearchTerm() {
      this.mnFormGroup.patchValue({searchTerm: ""});
    }
  })(window.rxjs);
