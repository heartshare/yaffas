Groups = function() {
	this.table = null;
	this.menu = null;
	this.setupTable();
}

Groups.prototype.editGroup = function() {
	var r = this.table.selectedRows();
	
	if (r.length > 0) {
		Yaffas.ui.openTab("/group/edit_groups.cgi", {groups: r[0][0], showform: 1})
	}
}
Groups.prototype.deleteGroup = function() {
	var r = this.table.selectedRows();
	
	if (r.length > 0) {
		var d = new Yaffas.Confirm(_("lbl_delete"), _("lbl_ask_delete")+dlg_arg(r[0][0]), function() {
			Yaffas.ui.submitURL("/group/rm_groups.cgi", {groups: r[0][0]})
		});
		d.show();
	}
}

Groups.prototype.setupTable = function() {
    var menuitems = [];

    if (Yaffas.PRODUCTS.include("fax")) {
        menuitems.push(
        {
            text: _("lbl_edit"),
            onclick: {
                fn: this.editGroup.bind(this)
            }
        }
        );
    }

	if (auth_type() === "local LDAP") {
		menuitems.push({
			text: _("lbl_delete"),
			onclick: {
				fn: this.deleteGroup.bind(this)
			}
		});
	}

	var columns = [
    {
        key: "group",
        label: _("lbl_groupname"),
        sortable: true
    }, {
        key: "users",
        label: _("lbl_user"),
        sortable: true,
    }, {
        key: "filetype",
        label: _("lbl_filetype"),
        sortable: true
    }
	];
		
	this.table = new Yaffas.Table({
		container: "table",
		columns: columns,
		url: "/group/groups.cgi",
		sortColumn: 0
	});

	this.menu = new Yaffas.Menu({container: "menu", trigger: "table", items: menuitems});
}

Groups.prototype.savedForm = function(url) {
	switch(url) {
		case "add_groups.cgi":
			Yaffas.ui.resetTab();
			this.table.reload();
			break;
		case "edit_groups.cgi":
			Yaffas.ui.closeTab();
			this.table.reload();
			break;
		case "rm_groups.cgi":
			this.table.reload();
			break;
	}
}

Groups.prototype.cleanup = function() {
	if (this.menu) {
		this.menu.destroy();
		this.menu = null;
	}
}

module = new Groups();
