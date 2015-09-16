#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <readline/readline.h>
#include <readline/history.h>


char *matches[4] = { "one", "two", "three", NULL };

char	*str_malloc(char *text) {
	char *p = malloc(strlen(text)+1);
	
	strcpy(p, text);
	return p;
}

char	*fred(const char *text, int state) {
	char		*p = NULL;
	static int 	i=0;
	fprintf(stderr, "text=%s  state=%d (i=%d)\n", text, state, i);

	if(state == 0) i=0;

	if(matches[i]) p = str_malloc(matches[i++]);
	
	return p;
}

char	**bill(const char *text, int start, int end) {
	char **matches;

	fprintf(stderr, "text=%s start=%d end=%d\n", text, start, end);
	matches = (char **)NULL;
	if(start == 0) matches = rl_completion_matches(text, fred);
	return matches;
}


int main(int argc, char *argv[]) {
	char *input;
	char shell_prompt[100];

//	rl_completion_entry_function = fred;
	rl_attempted_completion_function = bill;

	rl_bind_key('\t', rl_complete);
	
	for(;;) {
		snprintf(shell_prompt, sizeof(shell_prompt), "%s:%s $ ", getenv("USER"), getcwd(NULL, 1024));
	
		input = readline(shell_prompt);
	
		if(!input) break;

		add_history(input);

		free(input);
	}



	exit(0);
}


