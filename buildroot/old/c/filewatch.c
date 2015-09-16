#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <sys/inotify.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

#include "unit.h"
#include "filewatch.h"
#include "luafuncs.h"

/*
 * We have a unit_service_desc for the service_loop
 */
static struct unit_service_desc     u_svc;

/*
 * Internal data structure for tracking what we monitor
 */
struct filewatch_data {
	int		id;					// inotify id
	int		fid;				// function id
	char	*filename;			// malloced full path
	int		flags;
	int		fw_type;			// FW_LOG or FW_CHANGE
	int		log_fd;				// filehandle for log following
	char	*basename;			// ptr to the last bit of filename

	struct	filewatch_data	*nextchild;
	struct	filewatch_data	*next;
};

/*
 * Out main list of watches stuff...
 */
struct filewatch_data	*watched_paths;

/*
 * Buffer for reading from inotify
 */
char buffer[(sizeof(struct inotify_event)+NAME_MAX+1)*10];

// Early kernels didn't have this...
#ifndef IN_EXCL_UNLINK
#define IN_EXCL_UNLINK 0
#endif

/*==============================================================================
 * Some utility functions to find by id, filename, or basename
 *==============================================================================
 */
static struct filewatch_data *find_path(char *pathname) {
	struct filewatch_data *p = watched_paths;
	while(p) {
		if(strcmp(p->filename, pathname)==0) return p;
		p=p->next;
	}
	return 0;
}
static struct filewatch_data *find_child(struct filewatch_data *parent, char *basename) {
	struct filewatch_data *p = parent->nextchild;
	while(p) {
		if(strcmp(p->basename, basename)==0) return p;
		p=p->nextchild;
	}
	return 0;
}
static struct filewatch_data *find_by_id(int id) {
	struct filewatch_data *p = watched_paths;
	while(p) {
		struct filewatch_data *c = p->nextchild;

		if(p->id == id) return p;
		while(c) {
			if(c->id == id) return c;
			c = c->nextchild;
		}
		p=p->next;
	}
	return 0;
}
static struct filewatch_data *new_watch(char *filename) {
	struct filewatch_data *p = malloc(sizeof(struct filewatch_data));
	memset(p, 0, sizeof(struct filewatch_data));
	
	p->filename = malloc(strlen(filename)+1);
	strcpy(p->filename, filename);
	p->basename = strrchr(p->filename, '/')+1;
	return(p);
}
static void free_watch(struct filewatch_data *p) {
	free(p->filename);
	free(p);
}
static void unlink_path(struct filewatch_data *i) {
	struct filewatch_data *p = watched_paths->next;

	if(watched_paths == i) { watched_paths = i->next; return; }
	while(p) {
		if(p->next == i) { p->next = i->next; return; }
		p = p->next;
	}
}
static void unlink_child(struct filewatch_data *parent, struct filewatch_data *i) {
	struct filewatch_data *p = parent;

	while(p) {
		if(p->nextchild == i) { p->nextchild = i->nextchild; return; }
		p=p->nextchild;
	}
}

/*==============================================================================
 * Open (or re-open) the given log file...
 *==============================================================================
 */
static int reopen_log(struct filewatch_data *fwdata) {
	if(fwdata->log_fd > 0) close(fwdata->log_fd);
	fwdata->log_fd = open(fwdata->filename, O_RDONLY);
	return fwdata->log_fd;
}
void close_log(struct filewatch_data *fwdata) {
	if(fwdata->log_fd > 0) close(fwdata->log_fd);
}
int read_log(lua_State *L, struct filewatch_data *fwdata) {
	char			block[1024];
	int				rc;
	luaL_Buffer		b;
	struct stat		st;
	off_t			pos;

	if(fwdata->log_fd <= 0) reopen_log(fwdata);
	if(fwdata->log_fd <= 0) {
		fprintf(stderr, "unable to read logfile: %s\n", fwdata->filename);
		return 1;
	}
	luaL_buffinit(L, &b);

	// TODO: if the file has shrunk then rewind
	if(fstat(fwdata->log_fd, &st) != 0) {
		fprintf(stderr, "unable to stat file: %s\n", fwdata->filename);
	}
	pos = lseek(fwdata->log_fd, 0, SEEK_CUR);
	fprintf(stderr, "STARTING POS: %d\n", (int)pos);
	fprintf(stderr, "FILE SIZE: %d\n", (int)st.st_size);

	while((rc = read(fwdata->log_fd, block, sizeof(block))) > 0) {
		fprintf(stderr, "rc=%d\n", rc);
		luaL_addlstring(&b, block, rc);
	}
	fprintf(stderr, "rc=%d\n", rc);
	luaL_pushresult(&b);
	return 1;
}

/*==============================================================================
 * Add a file to the monitor list...
 *==============================================================================
 */
int filewatch_add(lua_State *L, int fid, int fd, char *filename, int flags, int fw_type) {
	struct filewatch_data	*fwpath, *fwfile;
	char					*slash;

	// First we see if we have a parent watcher already... if not add one!
	slash = strrchr(filename, '/');
	if(!slash || slash==filename) {
		fprintf(stderr, "full path required for filewatch_add\n");
		return 0;
	}
	*slash = 0;
	fwpath = find_path(filename);
	if(!fwpath) {
		fwpath = new_watch(filename);
		fwpath->id = inotify_add_watch(fd, filename, 
						IN_CREATE|IN_DELETE|IN_MOVED_FROM|IN_MOVED_TO);
		if(fwpath->id < 0) {
			free_watch(fwpath);
			fprintf(stderr, "unable to watch directory (%s)\n", filename);
			*slash = '/';
			return 0;
		}
		fprintf(stderr, "FILEWATCH: watching (%s) with id=%d\n", filename, fwpath->id);
		fwpath->next = watched_paths;
		watched_paths = fwpath;
	}
	*slash = '/';

	// Now we can add the file itself ... if it exists then great, if not
	// then we will wait for the parent to catch it.
	fwfile = new_watch(filename);
	
	// Set up the structure...
	fwfile->flags = flags;
	fwfile->fw_type = fw_type;
	fwfile->fid = fid;

	// Register for inotify...
	fwfile->id = inotify_add_watch(fd, filename, IN_MODIFY);
	
	if(fwfile->id == -1) {
		if(errno == ENOENT) {
			// the file doesn't exist yet ... we will catch the creation
		} else {
			fprintf(stderr, "notify_add failed: errno=%d\n", errno);
			free_watch(fwfile);
			return 0;
		}
	}
	// Add to parent list...
	fwfile->nextchild = fwpath->nextchild;
	fwpath->nextchild = fwfile;

	fprintf(stderr, "file registered with id=%d\n", fwfile->id);
	return 0;
}
int filewatch_remove(int fd, char *filename) {
	struct filewatch_data	*fwpath, *fwchild;
	char					*slash;
	int						fid;

	slash = strrchr(filename, '/');
	fprintf(stderr, "slash=%p\n", slash);
	if(!slash) return 0;

	*slash = 0;
	fwpath = find_path(filename);
	fprintf(stderr, "fwpath=%p (filename=%s)\n", fwpath, filename);
	if(!fwpath) { *slash = '/'; return 0; }

	fwchild = find_child(fwpath, slash+1);
	fprintf(stderr, "fwchild=%p (filename=%s)\n", fwchild, slash+1);
	if(!fwchild) { *slash = '/'; return 0; }

	// Stop watching the file...
	if(fwchild->id != -1) inotify_rm_watch(fd, fwchild->id);

	unlink_child(fwpath, fwchild);
	fid = fwchild->fid;
	free_watch(fwchild);
		fprintf(stderr, "removed file\n");
	if(!fwpath->nextchild) {
		inotify_rm_watch(fd, fwpath->id);
		unlink_path(fwpath);
		free_watch(fwpath);
		fprintf(stderr, "removed path as well\n");
	}
	fprintf(stderr, "removed watch fid=%d\n", fid);
	return fid;	
}
/*==============================================================================
 * Given a function id, call the function with the filename ad the action
 *==============================================================================
 */
void filewatch_event_call(lua_State *L, int fid, char *filename, char *action) {
	get_function(L, fid);
	if(!lua_isfunction(L, -1)) {
		fprintf(stderr, "filewatch_call: invalid function for file: %s\n", filename);
		return;
	}
	lua_pushstring(L, filename);
	lua_pushstring(L, action);
	lua_call(L, 2, 0);
}
void filewatch_log_call(lua_State *L, struct filewatch_data *fwdata) {
	get_function(L, fwdata->fid);
	if(!lua_isfunction(L, -1)) {
		fprintf(stderr, "filewatch_call: invalid function for file: %s\n", fwdata->filename);
		return;
	}
	lua_pushstring(L, fwdata->filename);
	read_log(L, fwdata);
	lua_call(L, 2, 0);
}

/*==============================================================================
 * This is the mail filewatch read function. It reads an inotify file structure
 * from the inotify file handle, then looks up the id, and processes the result
 *==============================================================================
 */
int filewatch_read(lua_State *L, int fd) {
	struct inotify_event	*event;
	int						len;
	int						i;
	struct filewatch_data	*fwdata, *fwchild;

	len = read(fd, buffer, sizeof(buffer));
	if(len < sizeof(struct inotify_event)) {
		fprintf(stderr, "inotify_read: len=%d expected at least=%d\n", len, (int)sizeof(struct inotify_event));
		return 1;
	}
	i = 0;
	while(i < len) {
		event = (struct inotify_event *)&buffer[i];
		i += sizeof(struct inotify_event) + event->len;

		fwdata = find_by_id(event->wd);
		if(!fwdata) {
			fprintf(stderr, "inotify_read: event id=%d mask=%d nofwdata\n", event->wd, event->mask);
			continue;
		}
		// Print the filename...
		fprintf(stderr, "FILE EVENT FOR: %s\n", fwdata->filename);	
		fprintf(stderr, "MASK is: %d\n", event->mask);

		if(event->mask & (IN_CREATE|IN_DELETE|IN_MOVED_FROM|IN_MOVED_TO|IN_EXCL_UNLINK)) {
			// This is an event on the parent directory...
			fwchild = find_child(fwdata, event->name);
			if(!fwchild) {
				fprintf(stderr, "NOT INTERESTED: file op: %s (%d)\n", event->name, event->mask);
				continue;
			}
			fprintf(stderr, "INTERESTED file: %s\n", fwchild->filename);
			if(event->mask & IN_CREATE) {
				// The file has appeared, so we need to try to monitor...
				// We have to assume that it's not already monitored
				fwchild->id = inotify_add_watch(fd, fwchild->filename, IN_MODIFY);
				fprintf(stderr, "monitoring the file, id=%d\n", fwchild->id);
				if(fwchild->fw_type == FW_LOG) reopen_log(fwchild);
				filewatch_event_call(L, fwchild->fid, fwchild->filename, "create");
				continue;
			} else if(event->mask & (IN_DELETE|IN_MOVED_FROM)) {
				inotify_rm_watch(fd, fwchild->id);
				fprintf(stderr, "stopped monitoring the file, id=%d\n", fwchild->id);
				fwchild->id = -1;
				if(fwchild->fw_type == FW_LOG) close_log(fwchild);
				filewatch_event_call(L, fwchild->fid, fwchild->filename, "delete");
				continue;
			} else if(event->mask & IN_MOVED_TO) {
				if(fwchild->id != -1) inotify_rm_watch(fd, fwchild->id);
				fwchild->id = inotify_add_watch(fd, fwchild->filename, IN_MODIFY);
				if(fwchild->fw_type == FW_LOG) reopen_log(fwchild);
				filewatch_event_call(L, fwchild->fid, fwchild->filename, "create");
				continue;
			}
		} else {
			// This should be a modify event for a file...
			// TODO: support WRITE_CLOSE...
			// TODO: logwatch isn't complete yet
			if(fwdata->fw_type == FW_LOG) {
				filewatch_log_call(L, fwdata);
				continue;
			}
			if(event->mask & IN_MODIFY) {
				fprintf(stderr, "modification event on file: %s\n", fwdata->filename);
				filewatch_event_call(L, fwdata->fid, fwdata->filename, "modify");
			} else {
				fprintf(stderr, "unknown event\n");
			}
		}
	}
	return 0;
}

/*==============================================================================
 * Add a file to be monitored for changes
 *==============================================================================
 */
static int add_monitor(lua_State *L, int type) {
	char    *filename = (char *)luaL_checkstring(L, 1);
	int		fid;
	int		rc;

	if(!lua_isfunction(L, 2)) return luaL_error(L, "expected function as second argument");
	lua_pushvalue(L, 2);
	fid = store_function(L);

	fprintf(stderr, "function reference is %d\n", fid);
	
	rc = filewatch_add(L, fid, u_svc.fd, filename, 0, type);
	fprintf(stderr, "filewatch add rc=%d\n", rc);

	lua_pushnumber(L, 0);
	return 1;
}
static int monitor_log(lua_State *L) {
	return add_monitor(L, FW_LOG);
}
static int monitor_file(lua_State *L) {
	return add_monitor(L, FW_CHANGE);
}

static int unmonitor(lua_State *L) {
	char    *filename = (char *)luaL_checkstring(L, 1);
	int		rc;

	rc = filewatch_remove(u_svc.fd, filename);
	fprintf(stderr, "filewatch remove rc=%d\n", rc);
	if(rc > 0) free_function(L, rc);

	lua_pushnumber(L, 0);
	return 1;
}

/*==============================================================================
* Provide our service data for the unit_service module
*==============================================================================
*/
static int get_service(lua_State *L) {
	lua_pushlightuserdata(L, (void *)&u_svc);
	return 1;
}

/*==============================================================================
 * These are the functions we export to Lua...
 *==============================================================================
 */
static const struct luaL_reg lib[] = {
	{"monitor_log", monitor_log},
	{"monitor_file", monitor_file},
	{"unmonitor", unmonitor},
	{"get_service", get_service},
	{NULL, NULL}
};

/*------------------------------------------------------------------------------
 * Main Library Entry Point ... just intialise all the functions
 *------------------------------------------------------------------------------
 */
int luaopen_filewatch(lua_State *L) {
	// Initialise the module...
	luaL_openlib(L, "filewatch", lib, 0);

	// Populate the service structure...
	u_svc.fd = inotify_init();
	u_svc.read_func = filewatch_read;
	u_svc.write_func = NULL;
	u_svc.need_write_func = NULL;

	// And register...
    register_service(L, &u_svc);
	return 1;
}

